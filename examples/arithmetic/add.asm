; Compute 7 + 5 and return the result as the process exit status.
; Run, then read the answer with `echo $?`. See docs/09-arithmetic.md.

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
_main:      mov     rax, 7
            mov     rbx, 5
            add     rax, rbx                ; rax = 12

            mov     rdi, rax                ; exit status = 12
            mov     rax, SYS_EXIT
            syscall
