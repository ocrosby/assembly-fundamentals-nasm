; Call `sum8(1, 2, 3, 4, 5, 6, 7, 8)` and return the sum (36) as
; the exit status. Six of the arguments go in registers per the
; System V AMD64 ABI; the remaining two are pushed on the stack
; because the ABI only reserves six integer register slots for
; arguments. This is where the "ABI" earns its name — with more
; than six args, the *stack* becomes part of the calling contract.
;
; New in this example: passing more arguments than the six
; register slots the System V AMD64 ABI reserves. The caller
; pushes args 8 and 7 (right-to-left) before the `call`; the
; callee reads them as `[rbp + 16]` and `[rbp + 24]` from inside
; its own frame.

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
    ; Args 7 and 8 go on the stack, pushed right-to-left. Two
    ; 8-byte pushes preserve 16-byte stack alignment (`rsp` is
    ; 16-aligned at entry, stays 16-aligned after `push 8; push 7`,
    ; is 8-mod-16 after `call` — matching what the callee expects).
    push 8                           ; arg 8
    push 7                           ; arg 7

    ; Args 1..6 go in the six integer arg registers.
    mov r9,  6                       ; arg 6
    mov r8,  5                       ; arg 5
    mov rcx, 4                       ; arg 4
    mov rdx, 3                       ; arg 3
    mov rsi, 2                       ; arg 2
    mov rdi, 1                       ; arg 1

    call sum8                        ; rax = 1+2+3+4+5+6+7+8 = 36
    add rsp, 16                      ; caller pops the two stack args

    mov rdi, rax                     ; arg 1: exit status = sum
    mov rax, SYS_EXIT
    syscall                          ; sys_exit(36)

; uint64_t sum8(a, b, c, d, e, f, g, h)
;   Register args (System V AMD64):
;     a in rdi, b in rsi, c in rdx, d in rcx, e in r8, f in r9
;   Stack args (7th arg onward), addressed via `rbp`:
;     [rbp + 0]  = saved caller rbp
;     [rbp + 8]  = return address (from `call`)
;     [rbp + 16] = g   (arg 7, first stack arg)
;     [rbp + 24] = h   (arg 8)
;   Result in rax.
sum8:
    push rbp
    mov rbp, rsp

    mov rax, rdi                     ; rax = a
    add rax, rsi                     ;      + b
    add rax, rdx                     ;      + c
    add rax, rcx                     ;      + d
    add rax, r8                      ;      + e
    add rax, r9                      ;      + f
    add rax, [rbp + 16]              ;      + g   (from the stack)
    add rax, [rbp + 24]              ;      + h   (from the stack)

    pop rbp
    ret
