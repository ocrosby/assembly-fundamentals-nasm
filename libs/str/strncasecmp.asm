; strncasecmp(a: rdi, b: rsi, n: rdx) -> signed int
;
; ASCII case-insensitive `strncmp`. Compares up to `n` bytes
; of two NUL-terminated strings byte-by-byte with `A`–`Z`
; folded to `a`–`z` on the fly. Every other byte is compared
; as-is. Semantics mirror `strncmp`:
;
;   0    the folded prefixes are equal for the first `n`
;        bytes, OR both strings hit '\0' at the same
;        position i < n
;   > 0  the first differing folded byte of `a` is greater
;   < 0  the first differing folded byte of `a` is smaller
;
; If `n = 0`, returns 0 without reading either pointer.
;
; Return value is in [-255, 255]; callers wanting the C
; `int` truncate the low 32 bits.

default rel

global strncasecmp

section .text

strncasecmp:
    xor   eax, eax                   ; equal-so-far result
    test  rdx, rdx
    jz    .done                      ; n == 0 → 0

    xor   ecx, ecx                   ; index i
.loop:
    movzx r8d, byte [rdi + rcx]      ; a[i] as unsigned
    movzx r9d, byte [rsi + rcx]      ; b[i] as unsigned

    ; Fold A..Z → a..z on a.
    mov   r10d, r8d
    sub   r10d, 'A'
    cmp   r10d, 'Z' - 'A'
    ja    .a_folded
    or    r8d, 0x20
.a_folded:
    ; Fold A..Z → a..z on b.
    mov   r10d, r9d
    sub   r10d, 'A'
    cmp   r10d, 'Z' - 'A'
    ja    .b_folded
    or    r9d, 0x20
.b_folded:
    sub   r8d, r9d                   ; signed difference [-255, 255]
    jnz   .diff
    ; Folded equal. If that byte is the terminator, both
    ; strings ended — the prefix is equal.
    test  r9d, r9d
    jz    .done
    inc   rcx
    cmp   rcx, rdx
    jb    .loop
    ret                              ; scanned n bytes, all matched

.diff:
    movsxd rax, r8d                  ; sign-extend into full rax
.done:
    ret
