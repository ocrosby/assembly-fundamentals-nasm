; The smallest program that does anything observable: ask the OS to
; terminate this process with status 0.
;
; New in this example: sections, entry symbols, syscall mechanics.

%ifdef MACOS
%define SYS_EXIT 0x2000001
%else
%define SYS_EXIT 60
%endif

            default rel
            global  _start
            global  _main

            section .text
_start:
_main:      mov     rax, SYS_EXIT
            xor     rdi, rdi                ; status = 0
            syscall
