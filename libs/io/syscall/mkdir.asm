; mkdir(path, mode) -> rax = 0 or -errno
;
; Create a directory at *path* with permission bits *mode*.
; The mode is filtered through the caller's umask, matching
; libc semantics — a caller that wants exact bits should
; either umask(0) first (out of libio's scope) or chmod after.
;
; Common failure paths: -EEXIST (already exists), -ENOENT
; (parent directory missing), -EACCES (parent not writable),
; -ENAMETOOLONG (path exceeds PATH_MAX).

%include "syscall.inc"

default rel

global mkdir

section .text

mkdir:
    mov rax, SYS_mkdir
    SYSCALL_NORM
    ret
