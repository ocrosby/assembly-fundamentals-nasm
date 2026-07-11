; getsockopt(fd, level, optname, optval, optlen) -> rax = 0 or -errno
;
; Reads a socket option. `level` selects the protocol level
; (SOL_SOCKET, IPPROTO_TCP, IPPROTO_IP, …); `optname` selects the
; option (SO_ERROR, SO_KEEPALIVE, TCP_NODELAY, …). The value is
; written to `*optval`, and `*optlen` is updated in place with
; the number of bytes written.

%include "syscall.inc"

default rel

global getsockopt

section .text

getsockopt:
    SYSCALL_ARG4                    ; optval: rcx -> r10
    mov rax, SYS_getsockopt
    SYSCALL_NORM
    ret
