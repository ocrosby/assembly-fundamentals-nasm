; Pass a `struct point` to a subroutine by pointer, have the
; subroutine mutate the struct's fields in place, and read the
; result back in the caller.
;
; The point starts at (10, 20). `translate(&pt, 3, 4)` moves it to
; (13, 24). The exit status is `pt.x + pt.y = 37`, which lets us
; see with one number that (a) the pointer reached the callee,
; (b) the callee mutated both fields, and (c) the caller read the
; mutated fields back.
;
; New in this example: passing a struct by **pointer**. Instead of
; loading each field into its own argument register, the caller
; loads one address into `rdi` — the callee walks the struct's
; fields via constant offsets from that pointer.

%ifdef MACOS
%define SYS_EXIT 0x2000001
%else
%define SYS_EXIT 60
%endif

; struct point { int64_t x; int64_t y; }
;   Field layout — one qword per field, so:
POINT_X equ 0
POINT_Y equ 8
POINT_SIZE equ 16

default rel
global _start
global _main

section .text

_start:
_main:
    ; translate(&pt, 3, 4)
    lea rdi, [pt]                    ; arg 1: pointer to the struct
    mov rsi, 3                       ; arg 2: dx
    mov rdx, 4                       ; arg 3: dy
    call translate

    ; Read the mutated fields back through the same pointer.
    lea rax, [pt]
    mov rdi, [rax + POINT_X]         ; rdi = pt.x  (13)
    add rdi, [rax + POINT_Y]         ;      + pt.y (13 + 24 = 37)

    mov rax, SYS_EXIT
    syscall                          ; sys_exit(37)

; void translate(point *p, int64_t dx, int64_t dy)
;   p in rdi, dx in rsi, dy in rdx.
;   Modifies *p in place; no return value in rax.
;
;   The RMW (read-modify-write) form `add [rdi + off], reg` is one
;   instruction — the CPU reads the memory operand, adds the
;   register, and writes the result back. No intermediate register
;   needed.
translate:
    add [rdi + POINT_X], rsi         ; p->x += dx
    add [rdi + POINT_Y], rdx         ; p->y += dy
    ret

section .data
; struct point { .x = 10, .y = 20 }
pt: dq 10, 20
