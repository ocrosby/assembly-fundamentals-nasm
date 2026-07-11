; wait4(pid, wstatus*, options, rusage*) -> rax = pid or -errno
;
; Suspend the calling process until one of its children changes
; state, then report which child and how. This is the classic
; BSD wait; POSIX `waitpid` is a subset (equivalent to
; wait4(pid, wstatus, options, NULL)).
;
; Arguments:
;   rdi = pid       > 0  wait for exactly this pid
;                   0    wait for any child in the caller's
;                        process group
;                   -1   wait for any child
;                   < -1 wait for any child in the process
;                        group |pid|
;   rsi = wstatus*  where to store the raw status word — pass
;                   NULL to discard it. Decode it with:
;                     WIFEXITED(x)   = (x & 0x7f) == 0
;                     WEXITSTATUS(x) = (x >> 8) & 0xff
;                     WIFSIGNALED(x) = ((x & 0x7f) + 1) >> 1 > 0
;                     WTERMSIG(x)    = x & 0x7f
;   rdx = options   0 for blocking wait; OR in WNOHANG to
;                   return 0 immediately when no child has
;                   exited, or WUNTRACED to also report
;                   stopped children.
;   rcx = rusage*   optional pointer to a struct rusage that
;                   the kernel fills with the child's resource
;                   consumption. NULL to skip. Uses libtime's
;                   struct rusage layout (ru_utime at 0,
;                   ru_stime at 16, plus the platform-varying
;                   tail).
;
; Return:
;   rax > 0         pid of the child that changed state
;   rax = 0         WNOHANG was set and no child was ready
;   rax = -errno    -ECHILD if the caller has no unwaited
;                   children matching pid, -EINTR if a signal
;                   handler ran during the wait

%include "syscall.inc"

default rel

global wait4

section .text

wait4:
    SYSCALL_ARG4                    ; rcx → r10
    mov rax, SYS_wait4
    SYSCALL_NORM
    ret
