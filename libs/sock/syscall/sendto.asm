; sendto(fd, buf, len, flags, addr, addrlen) -> rax = bytes sent or -errno
;
; Send on an unconnected socket (typical for SOCK_DGRAM/UDP) to
; the address at `addr`. On a connected socket, `addr` should
; be NULL and `addrlen` zero, matching send() semantics.

%include "syscall.inc"

default rel

global sendto

section .text

sendto:
    SYSCALL_ARG4                    ; flags: rcx -> r10
    mov rax, SYS_sendto
    SYSCALL_NORM
    ret
