; socketpair(domain, type, protocol, sv) -> rax = 0 or negative errno
;
; Creates a pair of connected sockets and writes their two fds
; to sv[0] and sv[1]. Only AF_UNIX is portable across BSDs and
; Linux; both SOCK_STREAM and SOCK_DGRAM are supported. Typical
; use is bidirectional IPC between a parent and child process
; after fork().

%include "syscall.inc"

default rel

global socketpair

section .text

socketpair:
    SYSCALL_ARG4                    ; sv: rcx -> r10
    mov rax, SYS_socketpair
    SYSCALL_NORM
    ret
