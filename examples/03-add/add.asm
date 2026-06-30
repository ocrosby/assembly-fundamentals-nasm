; Compute 7 + 5 and return the result (12) as the exit status. The
; calculation happens entirely in registers — no memory yet.
;
; New in this example: integer arithmetic with `add`. One register
; serves as both source and destination, which is the dominant form
; on x86-64 (two-operand encoding).

%ifdef MACOS
%define SYS_EXIT 0x2000001
%else
%define SYS_EXIT 60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    mov rax, 7                      ; first addend
    mov rbx, 5                      ; second addend
    add rax, rbx                    ; rax = rax + rbx = 12

    mov rdi, rax                    ; arg 1: exit status = result
    mov rax, SYS_EXIT
    syscall                         ; sys_exit(12)
