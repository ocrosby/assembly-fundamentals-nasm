; rmdir(path) -> rax = 0 or -errno
;
; Remove the directory entry at *path*. The directory must be
; empty (only `.` and `..`); a non-empty directory returns
; -ENOTEMPTY (or -EEXIST on some legacy BSDs — macOS returns
; -ENOTEMPTY).
;
; Symbolic links pointing at a directory are removed as themselves
; via unlink, not rmdir — rmdir on a symlink returns -ENOTDIR.

%include "syscall.inc"

default rel

global rmdir

section .text

rmdir:
    mov rax, SYS_rmdir
    SYSCALL_NORM
    ret
