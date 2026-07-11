; sendmsg(fd, msg, flags) -> rax = bytes sent or negative errno
;
; Scatter-send from a struct msghdr. Beyond what send()/sendto()
; expose, msghdr carries an iovec list (scatter-gather), an
; optional destination address, and control-message ancillary
; data (SCM_RIGHTS for fd passing, IP_PKTINFO, …).

%include "syscall.inc"

default rel

global sendmsg

section .text

sendmsg:
    mov rax, SYS_sendmsg
    SYSCALL_NORM
    ret
