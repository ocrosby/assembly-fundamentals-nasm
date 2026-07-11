; accept(fd, addr, addrlen) -> rax = new fd or negative errno
;
; Removes the first completed connection from a listening
; socket's queue and returns a new fd referring to that
; connection. If `addr` is non-NULL, the peer address is written
; there and `*addrlen` is updated in place with the number of
; bytes written. Pass `addr = NULL` and `addrlen = NULL` to
; discard the peer address.

%include "syscall.inc"

default rel

global accept

section .text

accept:
    mov rax, SYS_accept
    SYSCALL_NORM
    ret
