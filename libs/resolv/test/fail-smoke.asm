; fail-smoke.asm — exercise the failure branch of libresolv's
; own syscall wrapper (resolv_random) so the macOS SYSCALL_NORM
; neg-rax line is covered on every symbol the archive contributes.
;
; libresolv's other exports are pure computation (wire-encode,
; wire-decode) or orchestration (resolv_a). Only random.asm
; contains a fresh syscall; every other syscall the resolver
; makes goes through libsock's already-covered wrappers.
;
; Prints "PASS\n" and exits 0 when the wrapper returned a
; negative value from a call the kernel is guaranteed to reject.
; Prints "FAIL:<id>\n" and exits 1 otherwise. Sub-checks:
;
;   1 resolv_random(NULL, 1) → -EFAULT (both kernels dereference
;                              the buf pointer before returning)

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern resolv_random

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .text

_start:
_main:
    ; 1: resolv_random(NULL, 1) → negative errno
    mov byte [fail_id], '1'
    xor edi, edi
    mov esi, 1
    call resolv_random
    test rax, rax
    jns .fail

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall
