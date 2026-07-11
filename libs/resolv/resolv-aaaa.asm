; resolv_aaaa(name: rdi, resolver: rsi, port: rdx, out_ip: rcx)
;     -> rax = 0 (success) or negative errno
;
; The AAAA counterpart to resolv_a — resolves *name* to a single
; IPv6 address, writing the 16 network-order bytes to *out_ip*
; on success. CNAME chasing is handled by resolv_query in the
; same way as A lookups.
;
; Return convention matches resolv_a: 0 on success, -ENODATA
; when the response held no AAAA (and no CNAME chain resolved
; to one), or any of the RCODE-derived / socket-level errnos
; resolv_query passes through.

%include "syscall.inc"

default rel

extern resolv_query

global resolv_aaaa

section .text

%define TYPE_AAAA 28

resolv_aaaa:
    mov r8, rcx                     ; out_buf = out_ip
    mov ecx, TYPE_AAAA              ; qtype
    mov r9d, 1                      ; max_count
    call resolv_query

    test rax, rax
    js .propagate
    cmp rax, 1
    je .success
%ifdef MACOS
    mov rax, -96
%else
    mov rax, -61
%endif
    ret

.success:
    xor eax, eax
.propagate:
    ret
