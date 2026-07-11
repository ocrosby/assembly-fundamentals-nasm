; recvfrom(fd, buf, len, flags, addr, addrlen) -> rax = bytes (0=EOF) or -errno
;
; Receive on any socket, capturing the sender's address at
; `*addr` and updating `*addrlen` in place. Pass `addr = NULL`
; and `addrlen = NULL` to discard the sender address (equivalent
; to recv()).

%include "syscall.inc"

default rel

global recvfrom

section .text

recvfrom:
    SYSCALL_ARG4                    ; flags: rcx -> r10
    mov rax, SYS_recvfrom
    SYSCALL_NORM
    ret
