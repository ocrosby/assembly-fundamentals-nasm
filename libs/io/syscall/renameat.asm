; renameat(olddirfd, oldpath, newdirfd, newpath) -> rax = 0 or -errno
;
; The dirfd-scoped counterpart to `rename`. *oldpath* is
; resolved relative to *olddirfd*, *newpath* relative to
; *newdirfd*. Same atomic-move semantics as `rename` — a
; regular file may replace a regular file atomically, and
; cross-filesystem moves are rejected with -EXDEV.
;
; Takes four arguments; SYSCALL_ARG4 shifts *newdirfd* from
; rcx into r10 before the syscall.

%include "syscall.inc"

default rel

global renameat

section .text

renameat:
    SYSCALL_ARG4
    mov rax, SYS_renameat
    SYSCALL_NORM
    ret
