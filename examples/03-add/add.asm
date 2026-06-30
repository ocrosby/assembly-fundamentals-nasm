; Compute 7 + 5 and return the result (12) as the exit status. The
; calculation happens entirely in registers — no memory yet.
;
; New in this example: integer arithmetic with `add`, using one
; register as both source and destination.

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

            mov     rdi, rax
            mov     rax, SYS_EXIT
            syscall
