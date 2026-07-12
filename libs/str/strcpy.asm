; strcpy(dst: rdi, src: rsi) -> dst
;
; Copies a NUL-terminated string from `[src]` to `[dst]`,
; including the terminator, and returns the original `dst`
; pointer.
;
; Semantics match C's `strcpy`: the caller is responsible for
; ensuring `dst` has at least `strlen(src) + 1` bytes of
; space. There is no bounded variant here (`strncpy` has
; famously confusing semantics — callers who need a bounded
; copy should reach for `memcpy` after computing `strlen`
; explicitly).
;
; The buffers must not overlap; overlap is undefined behavior.

default rel

global strcpy

section .text

strcpy:
    mov rax, rdi                    ; preserve dst for return
.loop:
    movzx ecx, byte [rsi]           ; read src byte
    mov [rdi], cl                   ; write to dst
    test ecx, ecx
    jz .done                        ; wrote the terminator; stop
    inc rdi
    inc rsi
    jmp .loop
.done:
    ret
