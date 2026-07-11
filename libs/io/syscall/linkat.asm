; linkat(olddirfd, oldpath, newdirfd, newpath, flags) -> rax = 0 or -errno
;
; Create a HARD link — a second directory entry that refers to
; the same inode as the file at (olddirfd, oldpath). Both dirfd
; slots resolve their path relative to the referenced
; directory (or cwd, when AT_FDCWD is passed).
;
; The *flags* argument accepts AT_SYMLINK_FOLLOW (0x400 on
; Linux, 0x0040 on macOS — not exposed by libio yet since the
; smoke tests do not exercise it). With flags = 0, if the
; source is a symlink the link is created to the SYMLINK
; itself rather than to its target.
;
; Cross-filesystem hard links fail with -EXDEV; hard-linking
; a directory fails with -EPERM regardless of privileges on
; both platforms.
;
; Takes five arguments. SYSCALL_ARG4 moves *newdirfd* from rcx
; to r10; the 5th argument (*flags*) already lives in r8 which
; matches the syscall ABI slot.

%include "syscall.inc"

default rel

global linkat

section .text

linkat:
    SYSCALL_ARG4
    mov rax, SYS_linkat
    SYSCALL_NORM
    ret
