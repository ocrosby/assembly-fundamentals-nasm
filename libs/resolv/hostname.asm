; resolv_hostname_at (hosts_path: rdi, conf_path: rsi,
;                     name: rdx, out_ip: rcx)
; resolv_hostname_at6(hosts_path: rdi, conf_path: rsi,
;                     name: rdx, out_ip16: rcx)
;     -> rax = 0 or negative errno
;
; The composed entry points: look up *name* in the hosts-format
; file at *hosts_path* first; if not found, read the
; resolv.conf-format file at *conf_path* to enumerate DNS
; servers, and try each one in order until one succeeds. The
; v4 path delegates to resolv_a; the v6 path delegates to
; resolv_aaaa.
;
; v1.4 upgrade over v1.3: instead of reading only the first
; nameserver from resolv.conf, the composed entry now reads
; up to MAX_RESOLVERS entries via resolv_conf_read_all and
; tries them in listed order. On success the answer wins
; immediately. On a failure (any negative rax from resolv_a /
; resolv_aaaa), the last errno is remembered and the next
; resolver is tried. If every resolver fails, the last errno
; is returned.
;
; Return convention (all negative on failure):
;
;   0             *out_ip* populated with the resolved address
;                 (4 bytes for _at, 16 bytes for _at6)
;   -ENOENT       hosts miss + resolv.conf held no parseable
;                 nameserver
;   -ENODATA      at least one resolver responded but held no
;                 record of the requested family (passed
;                 through from resolv_a / resolv_aaaa)
;   any other negative errno from the file syscalls, socket
;   layer, or DNS decode step — whichever error the LAST
;   resolver in the list produced. Earlier failures are lost
;   intentionally so callers see the most-recent attempt's
;   errno rather than a cascade.
;
; The _at suffix mirrors POSIX openat() / fstatat() — this is
; the parameterized form. Callers that want the standard
; system paths reach for resolv_hostname / resolv_hostname6
; instead (below), which are short wrappers that pass
; "/etc/hosts" and "/etc/resolv.conf".
;
; ---- resolv_hostname (name: rdi, out_ip: rsi)
; ---- resolv_hostname6(name: rdi, out_ip16: rsi)
; ----                                       -> rax = 0 or -errno
;
; Convenience wrappers. Equivalent to
;   resolv_hostname_at ("/etc/hosts", "/etc/resolv.conf", name, out_ip)
;   resolv_hostname_at6("/etc/hosts", "/etc/resolv.conf", name, out_ip16)
; — the standard POSIX paths every consumer expects.

%include "syscall.inc"

default rel

extern resolv_hosts_lookup, resolv_hosts_lookup6
extern resolv_conf_read_all
extern resolv_a, resolv_aaaa

global resolv_hostname_at
global resolv_hostname
global resolv_hostname_at6
global resolv_hostname6

section .rodata
hosts_path:      db "/etc/hosts", 0
resolvconf_path: db "/etc/resolv.conf", 0

section .text

%define MAX_RESOLVERS  8
%define ENTRY_SIZE     8            ; struct {u32 ip; u16 port; u16 flags;}

; Stack frame for the _at variants:
;
;   [rsp+0 ..  +63]   resolver_list: MAX_RESOLVERS entries of
;                     8 bytes each (u32 ip net, u16 port host,
;                     u16 flags).
;   [rsp+64 .. +71]   LAST_ERROR: the errno from the most
;                     recent resolv_a / resolv_aaaa attempt.
;                     Left at -ENOENT if no resolver was tried.
;   [rsp+72 .. +79]   COUNT: how many entries resolv_conf_read_all
;                     produced (0..MAX_RESOLVERS).
;
; Total 80 bytes. Combined with the 5 callee-saved pushes
; (rbx, rbp, r12, r13, r14) and the return address the frame
; is 128 bytes — 16-byte aligned before any nested call.

%define LIST_OFF        0
%define LAST_ERROR_OFF  64
%define COUNT_OFF       72
%define FRAME_SIZE      80

; Register roles inside the _at variants:
;   rbx = hosts_path (unused after step 1)
;   rbp = conf_path (unused after step 2)
;   r12 = name
;   r13 = out_ip (4 or 16 bytes)
;   r14 = current entry pointer (advances by ENTRY_SIZE)
;   r15 = end-of-list pointer

; ---- resolv_hostname_at ----
resolv_hostname_at:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, FRAME_SIZE

    mov rbx, rdi                    ; hosts_path
    mov rbp, rsi                    ; conf_path
    mov r12, rdx                    ; name
    mov r13, rcx                    ; out_ip

    ; Default last-error to -ENOENT so if step 3 never runs
    ; (empty resolver list) the caller still sees the v1.3
    ; "nothing to look this up" signal.
    mov qword [rsp + LAST_ERROR_OFF], -2

    ; ---- 1: try /etc/hosts ----
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call resolv_hosts_lookup
    test rax, rax
    jz .done                        ; hit — out_ip already written
    cmp rax, -2
    jne .done                       ; real syscall error — propagate

    ; ---- 2: enumerate resolvers via /etc/resolv.conf ----
    mov rdi, rbp
    lea rsi, [rsp + LIST_OFF]
    mov edx, MAX_RESOLVERS
    call resolv_conf_read_all
    test rax, rax
    js .done                        ; syscall error — propagate
    mov [rsp + COUNT_OFF], rax
    test rax, rax
    jz .done                        ; empty list — LAST_ERROR is -ENOENT

    ; Cursor and end. Each entry is 8 bytes.
    lea r14, [rsp + LIST_OFF]
    lea r15, [r14 + rax * ENTRY_SIZE]

.try_next_v4:
    cmp r14, r15
    jae .exhausted

    ; resolv_a(name, resolver_ip, port, out_ip)
    mov rdi, r12
    mov esi, [r14 + 0]              ; ip (u32 net)
    movzx edx, word [r14 + 4]       ; port (u16 host)
    mov rcx, r13
    call resolv_a
    test rax, rax
    jz .done                        ; hit

    ; Remember error, try next.
    mov [rsp + LAST_ERROR_OFF], rax
    add r14, ENTRY_SIZE
    jmp .try_next_v4

.exhausted:
    mov rax, [rsp + LAST_ERROR_OFF]

.done:
    add rsp, FRAME_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- resolv_hostname ----
resolv_hostname:
    mov rdx, rdi                    ; name -> arg 3
    mov rcx, rsi                    ; out_ip -> arg 4
    lea rdi, [hosts_path]
    lea rsi, [resolvconf_path]
    jmp resolv_hostname_at

; ---- resolv_hostname_at6 ----
resolv_hostname_at6:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, FRAME_SIZE

    mov rbx, rdi
    mov rbp, rsi
    mov r12, rdx
    mov r13, rcx

    mov qword [rsp + LAST_ERROR_OFF], -2

    ; ---- 1: try /etc/hosts (v6 lines only) ----
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call resolv_hosts_lookup6
    test rax, rax
    jz .done
    cmp rax, -2
    jne .done

    ; ---- 2: enumerate resolvers ----
    mov rdi, rbp
    lea rsi, [rsp + LIST_OFF]
    mov edx, MAX_RESOLVERS
    call resolv_conf_read_all
    test rax, rax
    js .done
    mov [rsp + COUNT_OFF], rax
    test rax, rax
    jz .done

    lea r14, [rsp + LIST_OFF]
    lea r15, [r14 + rax * ENTRY_SIZE]

.try_next_v6:
    cmp r14, r15
    jae .exhausted

    ; resolv_aaaa(name, resolver_ip, port, out_ip16)
    mov rdi, r12
    mov esi, [r14 + 0]
    movzx edx, word [r14 + 4]
    mov rcx, r13
    call resolv_aaaa
    test rax, rax
    jz .done

    mov [rsp + LAST_ERROR_OFF], rax
    add r14, ENTRY_SIZE
    jmp .try_next_v6

.exhausted:
    mov rax, [rsp + LAST_ERROR_OFF]

.done:
    add rsp, FRAME_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- resolv_hostname6 ----
resolv_hostname6:
    mov rdx, rdi
    mov rcx, rsi
    lea rdi, [hosts_path]
    lea rsi, [resolvconf_path]
    jmp resolv_hostname_at6
