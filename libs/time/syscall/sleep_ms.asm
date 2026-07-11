; sleep_ms(ms) -> rax = 0 or -errno
;
; Suspend the calling thread for approximately `ms` milliseconds,
; then return. Implemented on both platforms as
; `poll(NULL, 0, ms)` — the well-known portable trick that
; borrows the millisecond timeout of the `poll` syscall to get a
; bounded sleep without pulling in `nanosleep` (which routes
; through `__semwait_signal` on macOS and needs a semaphore fd).
;
; Argument:
;   rdi = milliseconds to sleep (int32, non-negative)
;
; Return:
;   rax = 0            success, timeout expired
;   rax = -EINTR       a signal woke the sleep early
;
; A negative `ms` is passed through to the kernel as-is, which
; treats it as "wait forever" on both platforms — that's the
; caller's problem, not ours.
;
; Precision is bounded by the kernel's scheduler tick, so
; sub-millisecond sleeps effectively round up. For microsecond
; precision use gettimeofday deltas in a tight spin instead;
; for nanosecond precision on Linux, prefer nanosleep directly
; (not exported by libtime v1.1 because macOS has no numbered
; equivalent).

%include "syscall.inc"

default rel

global sleep_ms

section .text

sleep_ms:
    ; SysV: rdi=fds, rsi=nfds, rdx=timeout
    ; Caller gave us ms in rdi — shift it to rdx and clear the
    ; first two args.
    mov edx, edi                    ; timeout_ms
    xor edi, edi                    ; fds = NULL
    xor esi, esi                    ; nfds = 0
    mov rax, SYS_poll
    SYSCALL_NORM
    ret
