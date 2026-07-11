; stat(path, statbuf) -> rax = 0 or -errno
;
; Path-based counterpart to fstat. Populates *statbuf* with the
; same 144-byte struct fstat writes; the field offsets exported
; by syscall.inc (ST_SIZE_OFF, etc.) apply identically. Follows
; symbolic links along *path*; use lstat (deferred) to inspect
; the link itself.
;
; Common failure paths: -ENOENT (missing component), -EACCES
; (traversal denied), -ENAMETOOLONG (path too long), -ELOOP
; (symlink loop), -ENOTDIR (non-directory in the path).
;
; This wrapper is thin: the syscall takes two args directly in
; SysV positions and returns via SYSCALL_NORM's carry-flag
; normalization on macOS.

%include "syscall.inc"

default rel

global stat

section .text

stat:
    mov rax, SYS_stat
    SYSCALL_NORM
    ret
