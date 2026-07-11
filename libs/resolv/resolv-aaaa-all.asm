; resolv_aaaa_all(name: rdi, resolver: rsi, port: rdx,
;                 out_buf: rcx, max_count: r8)
;     -> rax = count copied (0..max_count) or negative errno
;
; The AAAA multi-record variant — same semantics as
; resolv_a_all but each returned record is 16 network-order
; bytes (an IPv6 address). Caller sizes out_buf as
; 16 * max_count bytes.

%include "syscall.inc"

default rel

extern resolv_query

global resolv_aaaa_all

section .text

%define TYPE_AAAA 28

resolv_aaaa_all:
    mov r9, r8
    mov r8, rcx
    mov ecx, TYPE_AAAA
    call resolv_query

    test rax, rax
    jnz .out
%ifdef MACOS
    mov rax, -96
%else
    mov rax, -61
%endif
.out:
    ret
