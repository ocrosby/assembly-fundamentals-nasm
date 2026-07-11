; resolv_a(name: rdi, resolver: rsi, port: rdx, out_ip: rcx)
;     -> rax = 0 (success) or negative errno
;
; Backward-compatible single-A-record resolver. Calls
; resolv_query with qtype=A (1), max_count=1, and translates the
; result:
;
;   count == 1 → 0 (out_ip populated with 4 network-order bytes)
;   count == 0 → -ENODATA (well-formed but no A records; a bare
;                CNAME with no A is treated as no-data)
;   negative  → propagate the errno unchanged
;
; v1.2 added CNAME chasing (up to 8 hops) inside resolv_query,
; so this wrapper transparently follows aliases.

%include "syscall.inc"

default rel

extern resolv_query

global resolv_a

section .text

%define TYPE_A 1

resolv_a:
    ; resolv_query(name, resolver, port, qtype=A, out_buf=out_ip, max_count=1)
    mov r8, rcx                     ; out_buf = out_ip
    mov ecx, TYPE_A                 ; qtype
    mov r9d, 1                      ; max_count
    call resolv_query

    ; Translate count → status.
    test rax, rax
    js .propagate                   ; negative errno: keep as-is
    cmp rax, 1
    je .success
    ; count == 0
%ifdef MACOS
    mov rax, -96                    ; -ENODATA on macOS
%else
    mov rax, -61                    ; -ENODATA on Linux
%endif
    ret

.success:
    xor eax, eax
.propagate:
    ret
