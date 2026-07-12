; sig_zero(set: rdi) -> void
;
; Clears every byte of the caller's sigset buffer to 0. After
; this call `sig_test(set, N)` returns 0 for every valid
; signal N — equivalent to POSIX `sigemptyset`.
;
; `set` must point at a buffer of at least SIGSET_BYTES bytes
; (4 on macOS, 8 on Linux — see `syscall/syscall.inc`). Callers
; who reserve `resq 1` (8 bytes) on both platforms get a
; portable buffer.
;
; Uses `rep stosb` for the clear. rcx and rdi are caller-saved
; per SysV, so the routine can clobber both without saving.

%include "syscall.inc"

default rel

global sig_zero

section .text

sig_zero:
    mov rcx, SIGSET_BYTES
    xor eax, eax                    ; store byte is al = 0
    rep stosb
    ret
