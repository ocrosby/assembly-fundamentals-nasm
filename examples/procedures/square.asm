; Call a procedure that squares its argument and return the result
; as the exit status. Expected: 7 * 7 = 49. See docs/14-procedures.md.

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
_main:      mov     rdi, 7                  ; arg 1 (System V AMD64)
            call    square                  ; rax = 49

            mov     rdi, rax                ; exit status = 49
            mov     rax, SYS_EXIT
            syscall

; int64_t square(int64_t x)  --  x in rdi, result in rax
square:     mov     rax, rdi
            imul    rax, rdi
            ret
