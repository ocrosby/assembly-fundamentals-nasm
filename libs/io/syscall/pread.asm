; pread(fd, buf, count, offset) -> rax = bytes read (0 = EOF) or -errno
;
; Positioned read: identical to read() except the file position
; is neither consulted nor modified — the read starts at the
; given `offset` and the fd's own position stays put. Useful for
; random-access parsers that need to look at multiple parts of
; the same file without juggling seek state.
;
; Takes four arguments; SYSCALL_ARG4 moves `offset` from rcx to
; r10 before the syscall.

%include "syscall.inc"

default rel

global pread

section .text

pread:
    SYSCALL_ARG4                    ; offset: rcx -> r10
    mov rax, SYS_pread
    SYSCALL_NORM
    ret
