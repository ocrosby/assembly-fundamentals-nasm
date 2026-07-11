; ftruncate(fd, length) -> rax = 0 or -errno
;
; Same as truncate but selects the file via an open fd rather
; than by name. The fd must have been opened for writing
; (O_RDWR or O_WRONLY); a read-only fd yields -EINVAL.
;
; ftruncate is the natural pairing with fstat: both take an fd,
; both leave the caller's file position untouched, both work on
; unlinked files (a file with no directory entry that a process
; still has open).

%include "syscall.inc"

default rel

global ftruncate

section .text

ftruncate:
    mov rax, SYS_ftruncate
    SYSCALL_NORM
    ret
