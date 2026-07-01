; Compute (a*a) + (b*b) for a=3, b=4 and return the result (25) as the
; exit status. The function uses a full frame-pointer prologue and
; stores its two intermediate squares as stack locals so a debugger
; can step through and watch them appear on the stack.
;
; New in this example: `push rbp` / `mov rbp, rsp` / `sub rsp, N`
; prologue, addressing stack locals as `[rbp - offset]`, and the
; matching `mov rsp, rbp` / `pop rbp` epilogue.

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
    mov rdi, 3                       ; a = 3     (arg 1)
    mov rsi, 4                       ; b = 4     (arg 2)
    call sum_of_squares              ; rax = 3*3 + 4*4 = 25

    mov rdi, rax                     ; arg 1: exit status = result
    mov rax, SYS_EXIT
    syscall                          ; sys_exit(25)

; uint64_t sum_of_squares(uint64_t a, uint64_t b)
;   a in rdi, b in rsi, result in rax.
;
; Stack frame after the prologue:
;
;     [rbp +  0] = saved caller rbp
;     [rbp -  8] = a * a   (first local)
;     [rbp - 16] = b * b   (second local)
sum_of_squares:
    push rbp                         ; save caller's frame pointer
    mov rbp, rsp                     ; establish new frame
    sub rsp, 16                      ; reserve 16 bytes for two int64 locals

    mov rax, rdi
    imul rax, rdi                    ; rax = a * a
    mov [rbp - 8], rax               ; store as first local

    mov rax, rsi
    imul rax, rsi                    ; rax = b * b
    mov [rbp - 16], rax              ; store as second local

    mov rax, [rbp - 8]
    add rax, [rbp - 16]              ; rax = a*a + b*b

    mov rsp, rbp                     ; release locals
    pop rbp                          ; restore caller's frame pointer
    ret
