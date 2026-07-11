; gettimeofday(tv, tz) -> rax = 0 or -errno
;
; Writes the current wall-clock time to *tv as a
; `struct timeval { time_t tv_sec; suseconds_t tv_usec; }`, and
; optionally writes the local timezone to *tz. The tz argument
; is deprecated on both platforms — pass NULL. Passing a
; non-NULL tz on modern kernels either fills obsolete fields
; (macOS) or is ignored (Linux); it is not portable.
;
; Precision is microseconds. Callers that need nanoseconds must
; wait for libtime v1.1 (which will grapple with the macOS
; clock_gettime situation — Darwin exposes `clock_gettime_nsec_np`
; at syscall 462, not the POSIX `clock_gettime`; see README).
;
; Callers should treat the wall clock as *wall clock* — subject
; to NTP jumps, DST transitions, and manual admin adjustments.
; For elapsed-time measurements pin two calls close together and
; subtract, and be prepared for a negative delta if the clock
; jumped backward between calls.

%include "syscall.inc"

default rel

global gettimeofday

section .text

gettimeofday:
%ifdef MACOS
    ; Darwin's SYS_gettimeofday takes THREE arguments, not two:
    ; (tv, tz, uint64_t *mach_absolute_time). Callers pin the
    ; POSIX 2-arg signature by convention, so we must zero the
    ; kernel-side 3rd argument ourselves — otherwise the kernel
    ; writes 8 bytes through whatever value rdx happens to
    ; carry, which is usually stack garbage from the caller.
    ; libtime v1.0 shipped without this, and the wrapper worked
    ; only because the asm smoke's bss layout absorbed the stray
    ; write silently. Any real caller with a non-zero rdx would
    ; have seen memory corruption.
    xor edx, edx
%endif
    mov rax, SYS_gettimeofday
    SYSCALL_NORM
    ret
