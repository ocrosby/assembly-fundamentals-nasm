; Call `make_rect(10, 20, 30, 40)` — a subroutine that constructs
; a `struct rect { int64_t x, y, w, h }` (32 bytes) and returns it
; **by value** to the caller. Because the struct is larger than 16
; bytes, the System V AMD64 ABI silently switches to a "return by
; hidden pointer" convention:
;
;   - The caller reserves space for the return value on its own
;     stack.
;   - The caller passes a pointer to that space as a hidden **first
;     argument** in `rdi`. The programmer-visible args shift right
;     by one: `x` lands in `rsi` (not `rdi`), `y` in `rdx`, and so
;     on.
;   - The callee stores each field through the hidden pointer,
;     then returns the same pointer in `rax`.
;   - The caller reads its fields back off its own stack.
;
; This looks nothing like the "return in rax" convention from
; earlier chapters, and it's not a NASM quirk — every C compiler on
; this ABI does exactly the same thing when a function returns a
; struct bigger than two registers can hold.
;
; The exit status is `x + y + w + h = 100`. One number that proves
; every field was stored and every field was read back.
;
; New in this example: returning a struct by value larger than 16
; bytes, the hidden-pointer calling convention, and shifting the
; "real" args by one register slot to make room for it.

%ifdef MACOS
%define MAIN_SYM _main
%else
%define MAIN_SYM main
%endif

; struct rect { int64_t x; int64_t y; int64_t w; int64_t h; }
;   Field layout — four qwords, 32 bytes total:
RECT_X equ 0
RECT_Y equ 8
RECT_W equ 16
RECT_H equ 24
RECT_SIZE equ 32

default rel
global MAIN_SYM

section .text

MAIN_SYM:
    ; Classic frame-pointer prologue: `push rbp` first restores
    ; 16-byte alignment (main entry has `rsp` at 8-mod-16 because
    ; the runtime's `call main` pushed a return address); the
    ; subsequent `sub rsp, 32` keeps us 16-aligned and reserves
    ; the space for our returned struct.
    push rbp
    mov  rbp, rsp
    sub  rsp, RECT_SIZE              ; 32 bytes on the stack for the rect

    ; Set up the call to `make_rect`. Because the return type is
    ; a big struct, the ABI reserves rdi for a hidden pointer to
    ; the caller's return slot. The programmer-visible args
    ; therefore shift right by one:
    ;   rdi = &return slot   (hidden)
    ;   rsi = x              (was arg 1)
    ;   rdx = y              (was arg 2)
    ;   rcx = w              (was arg 3)
    ;   r8  = h              (was arg 4)
    lea rdi, [rbp - RECT_SIZE]       ; hidden pointer to our rect
    mov rsi, 10                      ; x
    mov rdx, 20                      ; y
    mov rcx, 30                      ; w
    mov r8,  40                      ; h
    call make_rect                   ; rax comes back holding the same pointer

    ; Read the four fields the callee wrote for us, and sum them
    ; so a single number witnesses that every field survived.
    mov rax, [rbp - RECT_SIZE + RECT_X]     ; x
    add rax, [rbp - RECT_SIZE + RECT_Y]     ; + y
    add rax, [rbp - RECT_SIZE + RECT_W]     ; + w
    add rax, [rbp - RECT_SIZE + RECT_H]     ; + h  →  10 + 20 + 30 + 40 = 100

    ; Standard main epilogue: restore the frame and return.
    ; `eax` already holds our return status.
    mov rsp, rbp
    pop rbp
    ret

; rect *make_rect(rect *hidden, int64_t x, int64_t y, int64_t w, int64_t h)
;   The hidden pointer arrives in rdi; x, y, w, h in rsi, rdx, rcx, r8.
;   Stores each field through the hidden pointer, then returns the
;   same pointer in rax — the ABI mandates that a big-struct-
;   returning function's rax matches the hidden pointer the caller
;   passed in, so callers can chain `f().g` off the returned value.
make_rect:
    mov [rdi + RECT_X], rsi          ; hidden->x = x
    mov [rdi + RECT_Y], rdx          ; hidden->y = y
    mov [rdi + RECT_W], rcx          ; hidden->w = w
    mov [rdi + RECT_H], r8           ; hidden->h = h
    mov rax, rdi                     ; return the hidden pointer unchanged
    ret
