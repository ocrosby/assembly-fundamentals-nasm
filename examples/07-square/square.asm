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
global _start
global _main

section .text

_start:
_main:
    mov rdi, 7                      ; arg 1: x = 7
    call square                     ; rax = square(7) = 49; return address pushed onto stack

    mov rdi, rax                    ; arg 1: exit status = result
    mov rax, SYS_EXIT
    syscall                         ; sys_exit(49)

; int64_t square(int64_t x)
;   x      in rdi  (System V AMD64 arg 1)
;   result in rax  (System V AMD64 return value)
square:
    mov rax, rdi                    ; rax = x
    imul rax, rdi                   ; rax = x * x   (two-operand signed multiply)
    ret                             ; pop return address, jump to caller
