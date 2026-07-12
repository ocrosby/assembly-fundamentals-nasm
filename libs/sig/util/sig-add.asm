; sig_add(set: rdi, sig: rsi) -> void
;
; Set bit `(sig - 1)` in the caller's sigset buffer.
; Equivalent to POSIX `sigaddset`. After this call
; `sig_test(set, sig)` returns 1.
;
; Undefined behavior for `sig` outside the range 1..64 (Linux)
; or 1..32 (macOS). No bounds check — glibc's sigaddset does
; not do one either at optimized settings, and the caller
; usually passes a compile-time constant like `SIGPIPE`.
;
; Implementation uses `bts` (Bit Test and Set), which takes a
; bit index into a memory bitmap. For BTS with a memory
; operand and a 64-bit register bit index, the CPU computes
; the qword offset and bit-within-qword automatically — no
; manual divide/modulo needed.

%include "syscall.inc"

default rel

global sig_add

section .text

sig_add:
    ; The bit index is (sig - 1). Compute it in rax so the
    ; BTS below can use a 64-bit source register.
    lea rax, [rsi - 1]
    bts [rdi], rax
    ret
