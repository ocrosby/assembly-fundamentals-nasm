; getpid(void) -> rax = pid
;
; Returns the calling process's pid. Never fails on either
; platform — the wrapper is a straight pass-through of the
; single-instruction syscall. Zero arguments; the return value
; is a positive `pid_t`.
;
; getpid()'s value is stable for the lifetime of the process:
; the pid does not change across fork (each child gets its own
; fresh pid, but a given process's pid never mutates). Cache
; the return value once at startup if you use it in a hot path.

%include "syscall.inc"

default rel

global getpid

section .text

getpid:
    mov rax, SYS_getpid
    SYSCALL_NORM
    ret
