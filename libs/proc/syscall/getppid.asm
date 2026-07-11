; getppid(void) -> rax = parent pid
;
; Returns the pid of the calling process's parent. If the
; parent has already exited, the returned value is the pid of
; whichever process has since adopted this one — pid 1 (init /
; launchd) in the traditional model, or a chosen subreaper on
; Linux with PR_SET_CHILD_SUBREAPER.
;
; Never fails on either platform. Zero arguments; the return
; value is a positive `pid_t`.

%include "syscall.inc"

default rel

global getppid

section .text

getppid:
    mov rax, SYS_getppid
    SYSCALL_NORM
    ret
