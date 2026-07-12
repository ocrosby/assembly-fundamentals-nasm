; sig_test(set: rdi, sig: rsi) -> 0 or 1
;
; Return 1 if bit `(sig - 1)` in the caller's sigset buffer
; is set, 0 otherwise. Equivalent to POSIX `sigismember` on
; the success path.
;
; Same "no bounds check, undefined for out-of-range sig"
; contract as `sig_add` / `sig_del`. Uses `bt` (Bit Test)
; which loads the tested bit into the carry flag; `setc`
; then materializes the flag as an 8-bit value in `al` and
; `movzx` extends it to the full return width.

%include "syscall.inc"

default rel

global sig_test

section .text

sig_test:
    lea rax, [rsi - 1]
    bt [rdi], rax
    setc al                         ; al = CF
    movzx eax, al                   ; zero-extend to full rax
    ret
