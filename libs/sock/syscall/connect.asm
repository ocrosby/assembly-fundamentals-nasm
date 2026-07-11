; connect(fd, addr, addrlen) -> rax = 0 or negative errno
;
; Initiates a connection on a socket. For SOCK_STREAM this
; performs the full TCP handshake and blocks until it completes
; (or fails). For SOCK_DGRAM it fixes the default peer address so
; later send/recv calls target it. The sockaddr shape must match
; the socket's address family.

%include "syscall.inc"

default rel

global connect

section .text

connect:
    mov rax, SYS_connect
    SYSCALL_NORM
    ret
