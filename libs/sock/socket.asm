; socket(domain, type, protocol) -> rax = fd or negative errno
;
; Creates a communication endpoint. `domain` selects an address
; family (AF_INET, AF_INET6, AF_UNIX, …). `type` selects the
; socket semantics (SOCK_STREAM for reliable byte streams,
; SOCK_DGRAM for connectionless datagrams, SOCK_RAW, SOCK_SEQPACKET).
; `protocol` is 0 to pick the default protocol for the
; domain/type pair (TCP for AF_INET+SOCK_STREAM, UDP for
; AF_INET+SOCK_DGRAM).

%include "syscall.inc"

default rel

global socket

section .text

socket:
    mov rax, SYS_socket
    SYSCALL_NORM
    ret
