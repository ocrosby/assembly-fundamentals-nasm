; Compute factorial(5) = 120 and return the result as the exit
; status. The `factorial` subroutine calls itself — recursion in
; assembly is just the same `call` / `ret` from chapter 14 pointed at
; the current label.
;
; New in this example: recursion, and using a callee-saved register
; (`rbx`) to preserve the input across the recursive call — a
; lighter alternative to the full stack-frame prologue from
; 15-stack-frame when the function has no locals to spill.

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
    mov rdi, 5                       ; arg 1: n = 5
    call factorial                   ; rax = factorial(5) = 120

    mov rdi, rax                     ; arg 1: exit status = result
    mov rax, SYS_EXIT
    syscall                          ; sys_exit(120)

; uint64_t factorial(uint64_t n)
;   n      in rdi  (System V AMD64 arg 1)
;   result in rax  (System V AMD64 return value)
;
;   factorial(0) = factorial(1) = 1
;   factorial(n) = n * factorial(n-1)
;
; Uses `rbx` as scratch storage for `n` because rbx is callee-saved
; — the recursive call clobbers rdi but is guaranteed to preserve
; rbx. `push rbx` saves the caller's value on entry, `pop rbx`
; restores it before ret. Because we push one register (8 bytes),
; the stack goes from 8-mod-16 at entry to 16-aligned before the
; recursive call, matching what the callee expects.
factorial:
    cmp rdi, 1
    jbe .base_case                   ; n <= 1 -> return 1

    push rbx                         ; save caller's rbx
    mov rbx, rdi                     ; rbx = n  (survives the recursive call)

    dec rdi                          ; arg 1 for recursive call = n - 1
    call factorial                   ; rax = factorial(n - 1)

    imul rax, rbx                    ; rax = n * factorial(n - 1)

    pop rbx                          ; restore caller's rbx
    ret

.base_case:
    mov rax, 1                       ; factorial(0) = factorial(1) = 1
    ret
