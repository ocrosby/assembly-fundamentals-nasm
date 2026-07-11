; pwrite(fd, buf, count, offset) -> rax = bytes written or -errno
;
; Positioned write: identical to write() except the file
; position is neither consulted nor modified — the write starts
; at the given `offset`. On files opened with O_APPEND the
; kernel forces the offset to end-of-file regardless of the
; supplied value; that quirk is a POSIX oddity, not a libio
; behavior.
;
; Takes four arguments; SYSCALL_ARG4 moves `offset` from rcx to
; r10 before the syscall.

%include "syscall.inc"

default rel

global pwrite

section .text

pwrite:
    SYSCALL_ARG4                    ; offset: rcx -> r10
    mov rax, SYS_pwrite
    SYSCALL_NORM
    ret
