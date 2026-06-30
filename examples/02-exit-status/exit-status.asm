; Same as 01-exit-zero, but exit with status 42 so we can see a value
; flow from our code through the OS and back to the shell.
;
; New in this example: loading an immediate into a register with `mov`.

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
_main:      mov     rdi, 42                 ; status = 42
            mov     rax, SYS_EXIT
            syscall
