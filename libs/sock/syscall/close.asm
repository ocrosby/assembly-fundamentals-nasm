; close(fd) -> rax = 0 or negative errno
;
; Releases the file descriptor. For a connected TCP socket this
; triggers the closing handshake (FIN, ACK, …) after any queued
; outbound data is delivered. Prefer shutdown(fd, SHUT_WR)
; followed by close(fd) when the peer needs to distinguish an
; orderly close from a reset.

%include "syscall.inc"

default rel

global close

section .text

close:
    mov rax, SYS_close
    SYSCALL_NORM
    ret
