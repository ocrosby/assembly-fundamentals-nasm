; Call a procedure that squares its argument. The whole program
; reduces to `square(7)` returned via the exit status (49).
;
; New in this example: `call`/`ret`, and the System V AMD64 calling
; convention — arg 1 in `rdi`, return value in `rax`. `square` is a
; leaf function: it makes no further calls and uses only caller-saved
; registers, so no prologue is needed.

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
_main:      mov     rdi, 7                  ; arg 1
            call    square                  ; rax = 49

            mov     rdi, rax
            mov     rax, SYS_EXIT
            syscall

; int64_t square(int64_t x)  --  x in rdi, result in rax
square:     mov     rax, rdi
            imul    rax, rdi
            ret
