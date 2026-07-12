; memcmp(a: rdi, b: rsi, n: rdx) -> signed int
;
; Compares up to `n` bytes of `[a]` against `[b]`. Returns:
;
;   0    all n bytes are equal (or n == 0)
;   > 0  the first differing byte of `a` is numerically greater
;        than the corresponding byte of `b` (unsigned compare)
;   < 0  the first differing byte of `a` is smaller
;
; Semantics match C's `memcmp`: bytes are treated as **unsigned
; char**, so the sign of the return value comes from the unsigned
; subtraction of the first differing byte pair. The return value
; is a full signed 64-bit integer in rax; callers who need the
; classic C `int` can truncate — the value is always in the range
; [-255, 255].
;
; Byte-at-a-time is deliberate: this is a study-repo helper, and
; the fault-safety story ("stop at the first differing byte and
; never read past it") is clearer without SIMD or word-at-a-time
; games. Overlap between the buffers is legal — memcmp only reads.

default rel

global memcmp

section .text

memcmp:
    xor eax, eax                    ; equal-so-far result
    test rdx, rdx
    jz .done                        ; n == 0: return 0

    xor ecx, ecx                    ; index i
.loop:
    movzx r8d, byte [rdi + rcx]     ; a[i] as unsigned
    movzx r9d, byte [rsi + rcx]     ; b[i] as unsigned
    sub r8d, r9d                    ; signed difference in [-255, 255]
    jnz .diff
    inc rcx
    cmp rcx, rdx
    jb .loop
    ret                             ; all n matched, eax already 0

.diff:
    movsxd rax, r8d                 ; sign-extend into full rax
.done:
    ret
