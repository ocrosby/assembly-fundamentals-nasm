; setsockopt(fd, level, optname, optval, optlen) -> rax = 0 or -errno
;
; Sets a socket option. Common uses: SO_REUSEADDR before bind()
; on a listening socket, TCP_NODELAY on a stream socket to
; disable Nagle's algorithm, SO_RCVTIMEO/SO_SNDTIMEO to install a
; timeout on blocking I/O. `optval` points at the value; `optlen`
; is its byte size.

%include "syscall.inc"

default rel

global setsockopt

section .text

setsockopt:
    SYSCALL_ARG4                    ; optval: rcx -> r10
    mov rax, SYS_setsockopt
    SYSCALL_NORM
    ret
