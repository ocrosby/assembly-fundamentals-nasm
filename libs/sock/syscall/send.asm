; send(fd, buf, len, flags) -> rax = bytes sent or negative errno
;
; Send on a connected socket. Equivalent to
; sendto(fd, buf, len, flags, NULL, 0); implemented by invoking
; the sendto(2) syscall with a NULL destination address. `flags`
; is a bitmask (MSG_OOB, MSG_DONTWAIT, MSG_NOSIGNAL, …).

%include "syscall.inc"

default rel

global send

section .text

send:
    SYSCALL_ARG4                    ; flags: rcx -> r10
    xor r8, r8                      ; addr = NULL (arg 5)
    xor r9, r9                      ; addrlen = 0  (arg 6)
    mov rax, SYS_sendto
    SYSCALL_NORM
    ret
