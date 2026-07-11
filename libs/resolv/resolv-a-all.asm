; resolv_a_all(name: rdi, resolver: rsi, port: rdx,
;              out_buf: rcx, max_count: r8)
;     -> rax = count copied (0..max_count) or negative errno
;
; Multi-record variant. Populates *out_buf* with all A records
; the resolver returned, packed as consecutive 4-byte
; network-order IPv4 addresses. Caller sizes out_buf to hold up
; to *max_count* records (i.e. 4 * max_count bytes).
;
; Return convention:
;
;   count > 0 → this many records copied; if the response held
;               more, the extras were silently discarded
;   count == 0 → -ENODATA (no A records; a CNAME chain that
;                resolved back to another CNAME with no A also
;                lands here)
;   negative   → any of resolv_query's error paths (RCODE,
;                socket, wire malformed, CNAME hop limit)
;
; The two-value contract (count and -errno) shares the same rax
; slot; callers use `if (rax < 0)` for the failure test.

%include "syscall.inc"

default rel

extern resolv_query

global resolv_a_all

section .text

%define TYPE_A 1

resolv_a_all:
    ; Rewire args for resolv_query(name, resolver, port, qtype,
    ; out_buf, max_count). Our r8 is already the caller's max_count.
    mov r9, r8                      ; max_count → arg 6
    mov r8, rcx                     ; out_buf   → arg 5
    mov ecx, TYPE_A                 ; qtype     → arg 4
    call resolv_query

    ; Translate count == 0 → -ENODATA. Positive counts and
    ; negative errnos pass through.
    test rax, rax
    jnz .out
%ifdef MACOS
    mov rax, -96
%else
    mov rax, -61
%endif
.out:
    ret
