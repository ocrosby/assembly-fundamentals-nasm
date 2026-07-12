; strcasecmp(a: rdi, b: rsi) -> signed int
;
; ASCII case-insensitive `strcmp`. Compares two NUL-terminated
; strings byte-by-byte with `A`–`Z` folded to `a`–`z` on the
; fly. Every other byte — digits, punctuation, whitespace, and
; the high half (≥ 0x80) — is compared as-is. Return semantics
; match `strcmp`:
;
;   0    the folded strings are equal (both hit '\0' together)
;   > 0  the first differing folded byte of `a` is numerically
;        greater than the corresponding folded byte of `b`
;   < 0  the first differing folded byte of `a` is smaller
;
; The return value is in the range [-255, 255]; callers who
; want the traditional C `int` truncate the low 32 bits.
;
; Motivation: HTTP field names are case-insensitive
; (RFC 9110 §5.1). `Content-Type` and `content-type` compare
; equal; a strict `strcmp` would miss the alias. Case-fold at
; compare time avoids allocating a normalized copy of the
; header block.

default rel

global strcasecmp

section .text

strcasecmp:
.loop:
    movzx eax, byte [rdi]           ; a[i] as unsigned
    movzx ecx, byte [rsi]           ; b[i] as unsigned
    ; Fold A..Z → a..z on a. `sub` + unsigned range check +
    ; `or` avoids a branch mispredict on random ASCII text.
    mov   edx, eax
    sub   edx, 'A'
    cmp   edx, 'Z' - 'A'
    ja    .a_folded                  ; unsigned: outside A..Z
    or    eax, 0x20
.a_folded:
    ; Fold A..Z → a..z on b.
    mov   edx, ecx
    sub   edx, 'A'
    cmp   edx, 'Z' - 'A'
    ja    .b_folded
    or    ecx, 0x20
.b_folded:
    sub   eax, ecx                   ; signed difference [-255, 255]
    jnz   .diff
    ; Folded bytes equal. If that byte is the terminator, done —
    ; fold leaves '\0' at 0, so testing ecx (folded b) still
    ; sees the NUL.
    test  ecx, ecx
    jz    .done
    inc   rdi
    inc   rsi
    jmp   .loop

.diff:
    movsxd rax, eax                  ; sign-extend into full rax
.done:
    ret
