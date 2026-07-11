; getpeername(fd, addr, addrlen) -> rax = 0 or negative errno
;
; Reports the address of the peer the socket is connected to.
; Useful on the accept() side, where the peer address may have
; been discarded (addr=NULL) at accept time. `*addrlen` follows
; the same in/out semantics as getsockname().

%include "syscall.inc"

default rel

global getpeername

section .text

getpeername:
    mov rax, SYS_getpeername
    SYSCALL_NORM
    ret
