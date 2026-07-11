; recv(fd, buf, len, flags) -> rax = bytes received (0 = EOF) or -errno
;
; Receive on a connected socket. Equivalent to
; recvfrom(fd, buf, len, flags, NULL, NULL); implemented by
; invoking the recvfrom(2) syscall with NULL out-pointers.

%include "syscall.inc"

default rel

global recv

section .text

recv:
    SYSCALL_ARG4                    ; flags: rcx -> r10
    xor r8, r8                      ; addr = NULL
    xor r9, r9                      ; addrlen = NULL
    mov rax, SYS_recvfrom
    SYSCALL_NORM
    ret
