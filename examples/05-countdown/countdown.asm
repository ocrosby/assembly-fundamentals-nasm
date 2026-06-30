; Decrement rcx from 5 to 0, then exit. The program does no I/O —
; the loop is the entire point.
;
; New in this example: a local label (`.next`), the `dec`/`jnz` loop
; idiom (fewer instructions than `cmp`+jump because `dec` already
; sets the zero flag).

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
