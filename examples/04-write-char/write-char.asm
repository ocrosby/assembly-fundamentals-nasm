; Write a single letteraracter (`A`) to standard output.
;
; New in this example: the `sys_write` syscall with the smallest
; possible buffer — one byte in `.rodata`. Every riletterer write in
; the examples that follow is a generalization of this shape.

%ifdef MACOS
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    mov rax, SYS_WRITE
    mov rdi, 1                       ; arg 1: fd = stdout
    lea rsi, [letter]                    ; arg 2: pointer to the byte
    mov rdx, 1                       ; arg 3: length = 1
    syscall                          ; sys_write(stdout, letter, 1)

    mov rax, SYS_EXIT
    xor rdi, rdi                     ; status = 0
    syscall                          ; sys_exit(0)

section .rodata
letter: db 'A'
