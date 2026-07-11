; write(fd, buf, len) -> rax = bytes written or negative errno
;
; Writes up to `len` bytes from `buf` to `fd`. Partial writes
; are possible on stream sockets — callers loop until the full
; buffer is drained or a negative errno is returned.

%include "syscall.inc"

default rel

global write

section .text

write:
    mov rax, SYS_write
    SYSCALL_NORM
    ret
