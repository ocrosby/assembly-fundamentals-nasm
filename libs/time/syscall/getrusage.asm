; getrusage(who, rusage*) -> rax = 0 or -errno
;
; Reports resource usage — the fields most callers care about
; are the first two: `ru_utime` (user CPU time consumed) and
; `ru_stime` (kernel CPU time consumed), each a `struct timeval`
; at offsets 0 and 16.
;
; Arguments:
;   rdi = who        RUSAGE_SELF (0) — process totals
;                    RUSAGE_CHILDREN (-1) — sum over waited-on
;                    children
;   rsi = rusage*    caller-supplied `struct rusage` (>= 144 bytes)
;
; Return:
;   rax = 0          success, *rusage populated
;   rax = -EFAULT    rusage points outside the process's
;                    addressable space
;   rax = -EINVAL    who is neither RUSAGE_SELF nor
;                    RUSAGE_CHILDREN
;
; Layout notes: struct rusage's tail differs between platforms
; (Linux packs 16 more long fields; macOS packs 14 more). libtime
; exposes RU_UTIME_OFF and RU_STIME_OFF only — callers reading
; further fields must handle the per-platform width themselves,
; or stop at CPU time (which is what most benchmarking code
; actually wants).

%include "syscall.inc"

default rel

global getrusage

section .text

getrusage:
    mov rax, SYS_getrusage
    SYSCALL_NORM
    ret
