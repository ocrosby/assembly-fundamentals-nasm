; listen(fd, backlog) -> rax = 0 or negative errno
;
; Marks a bound socket as passive so it will accept incoming
; connections. `backlog` is the maximum length of the queue of
; pending, not-yet-accepted connections. The kernel silently caps
; excessive values (SOMAXCONN).

%include "syscall.inc"

default rel

global listen

section .text

listen:
    mov rax, SYS_listen
    SYSCALL_NORM
    ret
