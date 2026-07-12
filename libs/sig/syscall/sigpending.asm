; sigpending(set: rdi) -> 0 or -errno
;
; Fill `*set` with the set of signals that are pending delivery
; to the calling thread but have not yet been handled (usually
; because they are currently blocked). Useful in a
; block/critical-section/unblock pattern to check whether a
; signal was raised while it was masked.
;
; `set` must point at a sigset buffer at least SIGSET_BYTES
; wide (4 on macOS, 8 on Linux — see syscall.inc).
;
; Linux's `rt_sigpending(2)` takes a 2nd argument, `sigsetsize`,
; that must equal 8. macOS's BSD sigpending (syscall 52) is a
; single-arg call; the wrapper injects the 2nd arg on Linux
; and leaves rsi untouched on macOS.

%include "syscall.inc"

default rel

global sigpending

section .text

sigpending:
    mov rax, SYS_sigpending
%ifndef MACOS
    ; Linux: sigsetsize = 8 in rsi (the syscall's 2nd arg).
    mov rsi, SIGSET_BYTES
%endif
    SYSCALL_NORM
    ret
