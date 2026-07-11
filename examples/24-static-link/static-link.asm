; Print a greeting by calling print_string from libs/asm/libasm.a
; and exit with status 0 via sys_exit from the same archive.
;
; Both symbols are marked `extern`; the linker resolves them at
; link time by pulling the objects out of libasm.a. That is the
; only new machinery this example introduces on top of 23-macros.

default rel

extern print_string, sys_exit

global _start
global _main

section .rodata
msg:  db "Hello, static archive!", 10
mlen: equ $ - msg

section .text

_start:
_main:
    lea rdi, [msg]
    mov esi, mlen
    call print_string               ; sys_write(stdout, msg, mlen)

    xor edi, edi                    ; status = 0
    call sys_exit                   ; sys_exit(0) — does not return
