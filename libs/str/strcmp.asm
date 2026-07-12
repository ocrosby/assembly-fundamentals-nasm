; strcmp(a: rdi, b: rsi) -> signed int
;
; Compares two NUL-terminated strings byte-by-byte. Returns:
;
;   0    the strings are equal (both reached '\0' together)
;   > 0  the first differing byte of `a` is numerically greater
;        than the corresponding byte of `b` (unsigned compare)
;   < 0  the first differing byte of `a` is smaller
;
; The terminator is treated as an ordinary byte for the compare,
; which is what makes the "shorter string is less" behavior fall
; out for free: `"abc"` vs `"abcd"` differs at index 3, where `a`
; has `'\0'` (0) and `b` has `'d'` (100), so the result is negative.
;
; The return value is always in the range [-255, 255]; callers who
; want the traditional C `int` truncate the low 32 bits.

default rel

global strcmp

section .text

strcmp:
.loop:
    movzx eax, byte [rdi]           ; a[i] as unsigned
    movzx ecx, byte [rsi]           ; b[i] as unsigned
    sub eax, ecx                    ; signed difference in [-255, 255]
    jnz .diff
    ; a[i] == b[i]; if that shared byte is the terminator, we are
    ; done comparing (eax is already 0).
    test ecx, ecx
    jz .done
    inc rdi
    inc rsi
    jmp .loop

.diff:
    movsxd rax, eax                 ; sign-extend into full rax
.done:
    ret
