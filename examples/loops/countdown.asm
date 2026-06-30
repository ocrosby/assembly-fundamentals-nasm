; Decrement rcx from 5 to 0 and exit. The program does no I/O —
; the loop is the entire point. See docs/13-loops.md.

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
_main:      mov     rcx, 5
.next:      dec     rcx
            jnz     .next

            mov     rax, SYS_EXIT
            xor     rdi, rdi
            syscall
