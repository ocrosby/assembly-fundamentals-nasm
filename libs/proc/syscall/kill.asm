; kill(pid, sig) -> rax = 0 or -errno
;
; Send signal `sig` to process (or process group) `pid`.
;
; Arguments:
;   rdi = pid       > 0   send to this pid
;                   0     send to every process in the
;                         caller's process group
;                   -1    send to every process the caller has
;                         permission to signal (except pid 1)
;                   < -1  send to every process in the process
;                         group |pid|
;   rsi = sig       signal number, or 0 to check permission
;                   without actually delivering. sig = 0 is
;                   the canonical way to test "does pid still
;                   exist and am I allowed to signal it?" —
;                   returns 0 if yes, -ESRCH if the pid is
;                   gone, -EPERM if it exists but is out of
;                   reach.
;
; Return:
;   rax = 0         signal queued (or permission check ok)
;   rax = -ESRCH    no such process
;   rax = -EPERM    caller not permitted to signal this pid
;   rax = -EINVAL   sig is not a valid signal number

%include "syscall.inc"

default rel

global kill

section .text

kill:
    mov rax, SYS_kill
    SYSCALL_NORM
    ret
