; sig_del(set: rdi, sig: rsi) -> void
;
; Clear bit `(sig - 1)` in the caller's sigset buffer.
; Equivalent to POSIX `sigdelset`. After this call
; `sig_test(set, sig)` returns 0.
;
; Same "no bounds check, undefined for out-of-range sig"
; contract as `sig_add`. Same `btr` (Bit Test and Reset)
; instruction with the CPU-computed byte-and-bit split.

%include "syscall.inc"

default rel

global sig_del

section .text

sig_del:
    lea rax, [rsi - 1]
    btr [rdi], rax
    ret
