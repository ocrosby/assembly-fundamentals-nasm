; bind(fd, addr, addrlen) -> rax = 0 or negative errno
;
; Assigns a local address to the socket. `addr` points at a
; sockaddr structure whose shape depends on the socket's address
; family (sockaddr_in for AF_INET, sockaddr_in6 for AF_INET6,
; sockaddr_un for AF_UNIX). `addrlen` is the byte size of that
; structure.

%include "syscall.inc"

default rel

global bind

section .text

bind:
    mov rax, SYS_bind
    SYSCALL_NORM
    ret
