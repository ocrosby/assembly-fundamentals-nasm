; strchr(s: rdi, c: rsi) -> pointer or NULL
;
; Scans a NUL-terminated string starting at `[s]` for the
; first byte equal to the low 8 bits of `c`. Returns the
; pointer to that byte on a hit; returns NULL (0) on miss.
;
; Semantics match C's `strchr`: the terminator is treated as
; an ordinary byte for matching purposes, so `strchr(s, 0)`
; returns the pointer to the terminator itself rather than
; NULL. Only the low byte of `c` is meaningful.
;
; Byte-at-a-time; the routine reads no further than the
; terminator (or the matching byte, whichever comes first).

default rel

global strchr

section .text

strchr:
    movzx r8d, sil                  ; needle byte
.loop:
    movzx eax, byte [rdi]
    cmp eax, r8d
    je .hit
    ; No match this byte. If it was the terminator, we are
    ; done scanning — return NULL.
    test eax, eax
    jz .miss
    inc rdi
    jmp .loop

.miss:
    xor eax, eax                    ; NULL
    ret

.hit:
    mov rax, rdi                    ; pointer to matching byte
    ret
