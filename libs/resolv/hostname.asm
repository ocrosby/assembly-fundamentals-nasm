; resolv_hostname_at(hosts_path: rdi, conf_path: rsi,
;                    name: rdx, out_ip: rcx)
;     -> rax = 0 or negative errno
;
; The composed entry point for v1.1: look up *name* in the
; hosts-format file at *hosts_path* first; if not found, read
; the resolv.conf-format file at *conf_path* to pick a DNS
; server, and delegate to resolv_a() over UDP.
;
; Return convention (all negative on failure):
;
;   0             *out_ip* populated with the resolved address
;   -ENOENT       every step reported "not found":
;                   hosts had no match, resolv.conf had no
;                   parseable nameserver, or DNS returned
;                   NXDOMAIN
;   any other negative errno from the file syscalls or DNS
;
; The _at suffix mirrors POSIX openat() / fstatat() — this is
; the parameterized form. Callers that want the standard system
; paths reach for resolv_hostname() instead (below), which is a
; short wrapper that passes "/etc/hosts" and "/etc/resolv.conf".
; The parameterized form is what makes the smoke tests possible
; without touching real system files.
;
; ---- resolv_hostname(name: rdi, out_ip: rsi)
; ----                                       -> rax = 0 or -errno
;
; Convenience wrapper. Equivalent to
;   resolv_hostname_at("/etc/hosts", "/etc/resolv.conf",
;                     name, out_ip)
; — the standard POSIX paths every consumer expects.

%include "syscall.inc"

default rel

extern resolv_hosts_lookup, resolv_conf_read, resolv_a

global resolv_hostname_at
global resolv_hostname

section .rodata
hosts_path:    db "/etc/hosts", 0
resolvconf_path: db "/etc/resolv.conf", 0

section .text

%define DNS_PORT 53

; ---- resolv_hostname_at ----
resolv_hostname_at:
    push rbx
    push rbp
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; hosts_path
    mov rbp, rsi                    ; conf_path
    mov r12, rdx                    ; name
    mov r13, rcx                    ; out_ip

    ; ---- 1: try /etc/hosts ----
    ; resolv_hosts_lookup(hosts_path, name, out_ip)
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call resolv_hosts_lookup
    test rax, rax
    jz .done                        ; hit — out_ip already written

    ; Not -ENOENT means a real syscall error — propagate.
    cmp rax, -2
    jne .done

    ; ---- 2: read resolv.conf to pick a DNS server ----
    ; resolv_conf_read(conf_path, &resolver_ip)
    ; Use r14 (callee-saved) as the resolver-IP staging slot.
    ; A single dword is enough; we hold it in r14d.
    sub rsp, 8                      ; scratch slot for resolver IP
    mov rdi, rbp
    mov rsi, rsp
    call resolv_conf_read
    test rax, rax
    jnz .after_conf_read            ; failure — propagate

    mov r14d, [rsp]                 ; resolver IP (net order)

.after_conf_read:
    add rsp, 8
    test rax, rax
    jnz .done                       ; propagate the resolv_conf error

    ; ---- 3: resolv_a(name, resolver, port=53, out_ip) ----
    mov rdi, r12
    mov esi, r14d
    mov edx, DNS_PORT
    mov rcx, r13
    call resolv_a
    ; whatever resolv_a returned is our answer

.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- resolv_hostname ----
resolv_hostname:
    ; Rewire args: (name, out_ip) -> (hosts, conf, name, out_ip).
    mov rdx, rdi                    ; name -> arg 3
    mov rcx, rsi                    ; out_ip -> arg 4
    lea rdi, [hosts_path]
    lea rsi, [resolvconf_path]
    jmp resolv_hostname_at          ; tail call
