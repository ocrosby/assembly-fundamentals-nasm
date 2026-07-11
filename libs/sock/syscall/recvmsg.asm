; recvmsg(fd, msg, flags) -> rax = bytes received or negative errno
;
; Gather-receive into a struct msghdr. Populates the iovec list,
; the peer address if requested, and any ancillary control data
; the kernel or peer attached (SCM_RIGHTS, IP_TOS, …).
; `msg->msg_flags` is set by the kernel to report conditions
; like MSG_TRUNC or MSG_CTRUNC.

%include "syscall.inc"

default rel

global recvmsg

section .text

recvmsg:
    mov rax, SYS_recvmsg
    SYSCALL_NORM
    ret
