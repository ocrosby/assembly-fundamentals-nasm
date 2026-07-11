; resolv_hostname_at (hosts_path: rdi, conf_path: rsi,
;                     name: rdx, out_ip: rcx)
; resolv_hostname_at6(hosts_path: rdi, conf_path: rsi,
;                     name: rdx, out_ip16: rcx)
;     -> rax = 0 or negative errno
;
; The composed entry points: look up *name* in the hosts-format
; file at *hosts_path* first; if not found, read the
; resolv.conf-format file at *conf_path* to enumerate DNS
; servers, and try each one in listed order. If every resolver
; returns -ENOENT for a name that has NO dot in it, v1.5 falls
; back to search-domain iteration: it reads the file again for
; `search` / `domain` directives, composes each suffix onto
; the query name (`<name>.<suffix>`), and retries the resolver
; list.
;
; Return convention (all negative on failure):
;
;   0             *out_ip* populated with the resolved address
;                 (4 bytes for _at, 16 bytes for _at6)
;   -ENOENT       every attempt (hosts, all resolvers with the
;                 original name, and if applicable every
;                 search suffix) resolved to "name not found"
;   -ENODATA      at least one resolver answered but held no
;                 record of the requested family
;   any other negative errno from the file syscalls, socket
;   layer, or DNS decode step — whichever error the LAST
;   attempt produced
;
; v1.5 behavioral note:
;
;   * Search iteration ONLY fires for names with no '.' in them.
;     A name like "libresolv-ok.test" (one or more dots) is
;     treated as already qualified and never gets a suffix
;     appended.
;   * Search iteration ONLY fires when the resolver list rejected
;     the original name with -ENOENT. Hard errors (-ETIMEDOUT,
;     -ECONNREFUSED, -EIO, etc.) skip search and propagate.
;     This matches libc's stub resolver — transient errors
;     stop the walk; NXDOMAIN keeps it going.
;
; ---- resolv_hostname (name: rdi, out_ip: rsi)
; ---- resolv_hostname6(name: rdi, out_ip16: rsi)
; ----                                       -> rax = 0 or -errno
;
; Convenience wrappers. Equivalent to
;   resolv_hostname_at ("/etc/hosts", "/etc/resolv.conf", name, out_ip)
;   resolv_hostname_at6("/etc/hosts", "/etc/resolv.conf", name, out_ip16)

%include "syscall.inc"

default rel

extern resolv_hosts_lookup, resolv_hosts_lookup6
extern resolv_conf_read_all, resolv_conf_read_search
extern resolv_a, resolv_aaaa

global resolv_hostname_at
global resolv_hostname
global resolv_hostname_at6
global resolv_hostname6

section .rodata
hosts_path:      db "/etc/hosts", 0
resolvconf_path: db "/etc/resolv.conf", 0

section .text

%define MAX_RESOLVERS   8
%define ENTRY_SIZE      8            ; struct {u32 ip; u16 port; u16 flags;}
%define NAME_MAX        256          ; DNS FQDN limit is 253; pad for NUL
%define SEARCH_BUF_MAX  512          ; enough for a handful of suffixes

; Stack frame for the _at variants.
;
;   [rsp+0   .. +63]   resolver_list      — 8 * 8 = 64
;   [rsp+64  .. +71]   LAST_ERROR
;   [rsp+72  .. +79]   RESOLVER_COUNT
;   [rsp+80  .. +87]   LIST_END           — cached end pointer
;                                          for the resolver loop
;   [rsp+88  .. +95]   SEARCH_COUNT       — remaining suffixes
;   [rsp+96  .. +103]  SEARCH_CURSOR      — walker into
;                                          search_buf
;   [rsp+104 .. +111]  SEARCH_TRIED       — 0 = still on the
;                                          original name; 1 =
;                                          in the search-suffix
;                                          phase
;   [rsp+112 .. +367]  NAME_SCRATCH       — composed
;                                          "<name>.<suffix>"
;                                          (max 256 bytes)
;   [rsp+368 .. +879]  SEARCH_BUF         — packed NUL-terminated
;                                          suffixes from
;                                          resolv_conf_read_search
;
; Total 880 bytes. Combined with the 6 callee-saved pushes
; (rbx, rbp, r12, r13, r14, r15) and the return address the
; frame is 880 + 48 + 8 = 936. rsp is 16-byte aligned inside
; the frame: entry misalign 8, push adds 48 (0 mod 16), sub
; adds 880 (mod 16 = 0), total misalign = 8, so rsp % 16 = 8.
; Actual sub value must therefore be 872 to give aligned rsp.
;
; That algebra:
;   entry rsp % 16       = 8
;   after 6 pushes       = 8 (48 mod 16 = 0)
;   after sub rsp, X     = (8 - X) mod 16
;   want 0 → X mod 16 = 8
;
; 880 mod 16 = 0 — WRONG. Bump FRAME_SIZE to 872 (mod 16 = 8)
; which still fits every field. But 872 < 880, we lose 8 bytes.
; Trim SEARCH_BUF by 8 to 504.

%define LIST_OFF          0
%define LAST_ERROR_OFF    64
%define RESOLVER_COUNT_OFF 72
%define LIST_END_OFF      80
%define SEARCH_COUNT_OFF  88
%define SEARCH_CURSOR_OFF 96
%define SEARCH_TRIED_OFF  104
%define NAME_SCRATCH_OFF  112
%define SEARCH_BUF_OFF    368
%define SEARCH_BUF_LEN    504
%define FRAME_SIZE        872

; Register roles inside the _at variants (after prologue):
;   rbx = hosts_path
;   rbp = conf_path
;   r12 = ORIGINAL name (never mutated; needed for
;         search-composition and for the dot check)
;   r13 = out_ip / out_ip16
;   r14 = current query name pointer (starts at r12; becomes
;         &NAME_SCRATCH once the search phase kicks in)
;   r15 = current resolver-list walker (inside try_resolvers)

; ---- resolv_hostname_at ----------------------------------------
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

    mov qword [rsp + LAST_ERROR_OFF], -2
    mov qword [rsp + SEARCH_TRIED_OFF], 0

    ; ---- 1: try /etc/hosts ----
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call resolv_hosts_lookup
    test rax, rax
    jz .v4_success
    cmp rax, -2
    jne .v4_propagate

    ; ---- 2: enumerate resolvers ----
    mov rdi, rbp
    lea rsi, [rsp + LIST_OFF]
    mov edx, MAX_RESOLVERS
    call resolv_conf_read_all
    test rax, rax
    js .v4_propagate                ; syscall error
    mov [rsp + RESOLVER_COUNT_OFF], rax
    test rax, rax
    jz .v4_return_last_error        ; empty list — LAST_ERROR is -2

    ; ---- 3: try resolvers with the ORIGINAL name ----
    mov r14, r12

.v4_try_query:
    ; Cache the list end. Recomputed each pass because r14
    ; changes but the list itself does not.
    lea r15, [rsp + LIST_OFF]
    mov rax, [rsp + RESOLVER_COUNT_OFF]
    shl rax, 3                      ; * ENTRY_SIZE
    add rax, r15
    mov [rsp + LIST_END_OFF], rax

.v4_rl_next:
    cmp r15, [rsp + LIST_END_OFF]
    jae .v4_rl_exhausted

    ; resolv_a(name=r14, ip=[r15+0], port=[r15+4], out_ip=r13)
    mov rdi, r14
    mov esi, [r15 + 0]
    movzx edx, word [r15 + 4]
    mov rcx, r13
    call resolv_a
    test rax, rax
    jz .v4_success
    mov [rsp + LAST_ERROR_OFF], rax
    add r15, ENTRY_SIZE
    jmp .v4_rl_next

.v4_rl_exhausted:
    ; Every resolver failed for r14. Decide whether to try
    ; a search suffix.
    cmp qword [rsp + SEARCH_TRIED_OFF], 0
    jne .v4_search_next             ; already in search phase

    ; Fallback only fires on -ENOENT and only for a name with
    ; no dot in it.
    mov rax, [rsp + LAST_ERROR_OFF]
    cmp rax, -2
    jne .v4_return_last_error
    mov rdi, r12
    call name_has_dot
    test eax, eax
    jnz .v4_return_last_error

    ; Load the search list from conf_path.
    mov rdi, rbp
    lea rsi, [rsp + SEARCH_BUF_OFF]
    mov edx, SEARCH_BUF_LEN
    call resolv_conf_read_search
    test rax, rax
    jle .v4_return_last_error       ; no suffixes or read error
    mov [rsp + SEARCH_COUNT_OFF], rax
    lea rax, [rsp + SEARCH_BUF_OFF]
    mov [rsp + SEARCH_CURSOR_OFF], rax
    mov qword [rsp + SEARCH_TRIED_OFF], 1

.v4_search_next:
    mov rax, [rsp + SEARCH_COUNT_OFF]
    test rax, rax
    jz .v4_return_last_error
    dec qword [rsp + SEARCH_COUNT_OFF]

    ; Compose r12 . <current suffix> into NAME_SCRATCH.
    mov rdi, r12
    mov rsi, [rsp + SEARCH_CURSOR_OFF]
    lea rdx, [rsp + NAME_SCRATCH_OFF]
    mov ecx, NAME_MAX
    call compose_name
    test eax, eax
    js .v4_return_last_error        ; overflow — abandon search

    ; Advance SEARCH_CURSOR past the suffix we just used.
    mov rax, [rsp + SEARCH_CURSOR_OFF]
.v4_adv_suffix:
    mov cl, [rax]
    inc rax
    test cl, cl
    jnz .v4_adv_suffix
    mov [rsp + SEARCH_CURSOR_OFF], rax

    ; Retry with composed name.
    lea r14, [rsp + NAME_SCRATCH_OFF]
    jmp .v4_try_query

.v4_success:
    xor eax, eax
    jmp .v4_done

.v4_return_last_error:
    mov rax, [rsp + LAST_ERROR_OFF]

.v4_propagate:
.v4_done:
    add rsp, FRAME_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- resolv_hostname -------------------------------------------
resolv_hostname:
    mov rdx, rdi
    mov rcx, rsi
    lea rdi, [hosts_path]
    lea rsi, [resolvconf_path]
    jmp resolv_hostname_at

; ---- resolv_hostname_at6 ---------------------------------------
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
    mov qword [rsp + SEARCH_TRIED_OFF], 0

    ; ---- 1: hosts (v6) ----
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call resolv_hosts_lookup6
    test rax, rax
    jz .v6_success
    cmp rax, -2
    jne .v6_propagate

    ; ---- 2: enumerate resolvers ----
    mov rdi, rbp
    lea rsi, [rsp + LIST_OFF]
    mov edx, MAX_RESOLVERS
    call resolv_conf_read_all
    test rax, rax
    js .v6_propagate
    mov [rsp + RESOLVER_COUNT_OFF], rax
    test rax, rax
    jz .v6_return_last_error

    mov r14, r12

.v6_try_query:
    lea r15, [rsp + LIST_OFF]
    mov rax, [rsp + RESOLVER_COUNT_OFF]
    shl rax, 3
    add rax, r15
    mov [rsp + LIST_END_OFF], rax

.v6_rl_next:
    cmp r15, [rsp + LIST_END_OFF]
    jae .v6_rl_exhausted

    ; resolv_aaaa(name, ip, port, out_ip16)
    mov rdi, r14
    mov esi, [r15 + 0]
    movzx edx, word [r15 + 4]
    mov rcx, r13
    call resolv_aaaa
    test rax, rax
    jz .v6_success
    mov [rsp + LAST_ERROR_OFF], rax
    add r15, ENTRY_SIZE
    jmp .v6_rl_next

.v6_rl_exhausted:
    cmp qword [rsp + SEARCH_TRIED_OFF], 0
    jne .v6_search_next

    mov rax, [rsp + LAST_ERROR_OFF]
    cmp rax, -2
    jne .v6_return_last_error
    mov rdi, r12
    call name_has_dot
    test eax, eax
    jnz .v6_return_last_error

    mov rdi, rbp
    lea rsi, [rsp + SEARCH_BUF_OFF]
    mov edx, SEARCH_BUF_LEN
    call resolv_conf_read_search
    test rax, rax
    jle .v6_return_last_error
    mov [rsp + SEARCH_COUNT_OFF], rax
    lea rax, [rsp + SEARCH_BUF_OFF]
    mov [rsp + SEARCH_CURSOR_OFF], rax
    mov qword [rsp + SEARCH_TRIED_OFF], 1

.v6_search_next:
    mov rax, [rsp + SEARCH_COUNT_OFF]
    test rax, rax
    jz .v6_return_last_error
    dec qword [rsp + SEARCH_COUNT_OFF]

    mov rdi, r12
    mov rsi, [rsp + SEARCH_CURSOR_OFF]
    lea rdx, [rsp + NAME_SCRATCH_OFF]
    mov ecx, NAME_MAX
    call compose_name
    test eax, eax
    js .v6_return_last_error

    mov rax, [rsp + SEARCH_CURSOR_OFF]
.v6_adv_suffix:
    mov cl, [rax]
    inc rax
    test cl, cl
    jnz .v6_adv_suffix
    mov [rsp + SEARCH_CURSOR_OFF], rax

    lea r14, [rsp + NAME_SCRATCH_OFF]
    jmp .v6_try_query

.v6_success:
    xor eax, eax
    jmp .v6_done

.v6_return_last_error:
    mov rax, [rsp + LAST_ERROR_OFF]

.v6_propagate:
.v6_done:
    add rsp, FRAME_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- resolv_hostname6 ------------------------------------------
resolv_hostname6:
    mov rdx, rdi
    mov rcx, rsi
    lea rdi, [hosts_path]
    lea rsi, [resolvconf_path]
    jmp resolv_hostname_at6

; ---- name_has_dot ---------------------------------------------
; Input:  rdi = C-string.
; Output: eax = 1 if any '.' is present, else 0.
; Clobbers: rcx.
name_has_dot:
    xor eax, eax
.nhd_loop:
    mov cl, [rdi]
    test cl, cl
    jz .nhd_done
    cmp cl, '.'
    je .nhd_hit
    inc rdi
    jmp .nhd_loop
.nhd_hit:
    mov eax, 1
.nhd_done:
    ret

; ---- compose_name ---------------------------------------------
; Build "<name>.<suffix>" into a caller buffer.
;
; Input:  rdi = name (C-string)
;         rsi = suffix (C-string)
;         rdx = destination buffer
;         ecx = destination capacity (must include NUL)
; Output: eax = number of bytes written, excluding NUL, OR
;               -1 if the destination would overflow (nothing
;               is guaranteed about the buffer contents in
;               that case — callers should treat as failure).
; Clobbers: rax, r8, r9, r10, r11.
compose_name:
    mov r8, rdx                     ; write cursor
    mov r9d, ecx                    ; remaining bytes
    xor r11d, r11d                  ; bytes written

    ; Copy name.
    mov r10, rdi
.cn_name:
    mov al, [r10]
    test al, al
    jz .cn_name_end
    test r9d, r9d
    jz .cn_overflow
    mov [r8], al
    inc r8
    inc r10
    dec r9d
    inc r11d
    jmp .cn_name
.cn_name_end:

    ; Append '.'
    test r9d, r9d
    jz .cn_overflow
    mov byte [r8], '.'
    inc r8
    dec r9d
    inc r11d

    ; Copy suffix.
    mov r10, rsi
.cn_suffix:
    mov al, [r10]
    test al, al
    jz .cn_suffix_end
    test r9d, r9d
    jz .cn_overflow
    mov [r8], al
    inc r8
    inc r10
    dec r9d
    inc r11d
    jmp .cn_suffix
.cn_suffix_end:

    ; NUL terminator (does not count in return value).
    test r9d, r9d
    jz .cn_overflow
    mov byte [r8], 0

    mov eax, r11d
    ret

.cn_overflow:
    mov eax, -1
    ret
