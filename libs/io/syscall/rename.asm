; rename(oldpath, newpath) -> rax = 0 or -errno
;
; Atomically move the directory entry at *oldpath* to
; *newpath*. If *newpath* exists and is compatible with
; *oldpath*, it is replaced in a single kernel step — so a
; regular file over a regular file swaps atomically, and a
; process reading *newpath* through the old inode continues
; to work.
;
; Cross-filesystem moves are rejected with -EXDEV on both
; platforms — the kernel refuses to fake a rename with
; copy+delete, and callers that want that must do it
; explicitly.
;
; Directory semantics: macOS returns -ENOTEMPTY when
; *newpath* is a non-empty directory; Linux allows the
; replacement only if *newpath* is an EMPTY directory (also
; -ENOTEMPTY otherwise). Both agree that renaming a file
; over a directory (or vice versa) fails with -EISDIR /
; -ENOTDIR respectively.

%include "syscall.inc"

default rel

global rename

section .text

rename:
    mov rax, SYS_rename
    SYSCALL_NORM
    ret
