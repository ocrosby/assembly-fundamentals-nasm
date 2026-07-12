; memset(dst: rdi, c: rsi, n: rdx) -> dst
;
; Writes the low byte of `c` into `n` consecutive bytes starting
; at `[dst]` and returns the original `dst` pointer. Uses `rep
; stosb`, which mirrors `memcpy`'s `rep movsb`.
;
; Semantics match C's `memset`: only the low 8 bits of `c` are
; meaningful; the upper bits of the argument are ignored. `n = 0`
; is legal and returns `dst` unchanged.
;
; SysV passes `c` in rsi as a full 64-bit register; the actual
; byte-store instruction reads `al`. r8 holds the caller's dst
; across `stosb` because `stosb` autoincrements rdi.

default rel

global memset

section .text

memset:
    mov r8, rdi                     ; preserve dst for return
    mov al, sil                     ; byte value the store uses
    mov rcx, rdx                    ; rep stosb wants the count in rcx
    rep stosb                       ; store al into rcx bytes at [rdi]
    mov rax, r8                     ; return original dst
    ret
