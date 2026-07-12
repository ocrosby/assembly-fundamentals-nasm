; strncmp(a: rdi, b: rsi, n: rdx) -> signed int
;
; Compares up to `n` bytes of two NUL-terminated strings.
; Returns:
;
;   0    the strings are equal for the first `n` bytes, OR
;        both strings hit '\0' at the same position i < n
;   > 0  the first differing byte of `a` is numerically
;        greater than the corresponding byte of `b`
;   < 0  the first differing byte of `a` is smaller
;
; Semantics match C's `strncmp`: bytes are treated as
; **unsigned char**; the compare stops at the first '\0'
; shared by both sides even if `n` bytes remain. If `n = 0`,
; returns 0 without reading anything.
;
; Return value is a signed 64-bit int in rax, always in the
; range [-255, 255]; callers wanting the traditional C `int`
; truncate the low 32 bits.

default rel

global strncmp

section .text

strncmp:
    xor eax, eax                    ; equal-so-far result
    test rdx, rdx
    jz .done                        ; n == 0: return 0

    xor ecx, ecx                    ; index i
.loop:
    movzx r8d, byte [rdi + rcx]     ; a[i] as unsigned
    movzx r9d, byte [rsi + rcx]     ; b[i] as unsigned
    sub r8d, r9d                    ; signed difference in [-255, 255]
    jnz .diff
    ; a[i] == b[i]; if that shared byte is the terminator,
    ; the strings are equal for the whole compared range.
    test r9d, r9d
    jz .done
    inc rcx
    cmp rcx, rdx
    jb .loop
    ret                             ; scanned n bytes, all matched

.diff:
    movsxd rax, r8d                 ; sign-extend into full rax
.done:
    ret
