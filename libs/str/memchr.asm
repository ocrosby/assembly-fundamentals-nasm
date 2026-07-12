; memchr(s: rdi, c: rsi, n: rdx) -> pointer or NULL
;
; Scans up to `n` bytes of `[s]` for the first byte equal to
; the low 8 bits of `c`. Returns the pointer to that byte on
; a hit; returns NULL (0) on miss (either `n = 0` or every
; byte scanned differed).
;
; Semantics match C's `memchr`: only the low byte of `c` is
; meaningful, and the search is bounded by `n` rather than
; by a terminator. Overlap with the search buffer is legal —
; memchr only reads.
;
; Byte-at-a-time is deliberate; the routine reads at most `n`
; bytes and never overshoots the input buffer.

default rel

global memchr

section .text

memchr:
    test rdx, rdx
    jz .miss                        ; n == 0: no bytes to scan

    movzx r8d, sil                  ; needle byte
    xor ecx, ecx                    ; index i
.loop:
    movzx eax, byte [rdi + rcx]
    cmp eax, r8d
    je .hit
    inc rcx
    cmp rcx, rdx
    jb .loop

.miss:
    xor eax, eax                    ; NULL
    ret

.hit:
    lea rax, [rdi + rcx]            ; pointer to matching byte
    ret
