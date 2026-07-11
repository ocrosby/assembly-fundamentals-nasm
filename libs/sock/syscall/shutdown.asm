; shutdown(fd, how) -> rax = 0 or negative errno
;
; Disables further send and/or receive on a connected socket
; without releasing the fd itself. `how` is SHUT_RD (0) to
; disable further reads, SHUT_WR (1) to disable further writes
; (this sends the TCP FIN so the peer sees EOF), or SHUT_RDWR
; (2) to disable both.

%include "syscall.inc"

default rel

global shutdown

section .text

shutdown:
    mov rax, SYS_shutdown
    SYSCALL_NORM
    ret
