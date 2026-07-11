; getsockname(fd, addr, addrlen) -> rax = 0 or negative errno
;
; Reports the local address the socket is bound to. Useful when
; the local port was assigned dynamically (bind() with port 0).
; `*addrlen` must contain the buffer size on entry and is
; overwritten with the number of bytes actually written.

%include "syscall.inc"

default rel

global getsockname

section .text

getsockname:
    mov rax, SYS_getsockname
    SYSCALL_NORM
    ret
