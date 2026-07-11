; lstat(path, statbuf) -> rax = 0 or -errno
;
; Path-based stat that does NOT follow the terminal symlink —
; if *path* names a symbolic link, lstat writes metadata about
; the link itself (mode is S_IFLNK, st_size is the length of
; the link target string). The intermediate directory components
; are still resolved as symlinks, matching stat's behavior for
; those.
;
; Same 144-byte struct layout as stat / fstat.

%include "syscall.inc"

default rel

global lstat

section .text

lstat:
    mov rax, SYS_lstat
    SYSCALL_NORM
    ret
