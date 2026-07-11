; unlinkat(dirfd, path, flags) -> rax = 0 or -errno
;
; The dirfd-scoped counterpart to `unlink`. Path is resolved
; relative to *dirfd*, or absolutely if *path* starts with '/'.
; The special dirfd value AT_FDCWD makes the call semantically
; identical to `unlink(path)`.
;
; The *flags* argument accepts AT_REMOVEDIR — when set, the
; entry must be an empty directory and the operation succeeds
; only when `rmdir` would. This is how libc implements
; `rmdirat` (which POSIX did not standardize).

%include "syscall.inc"

default rel

global unlinkat

section .text

unlinkat:
    mov rax, SYS_unlinkat
    SYSCALL_NORM
    ret
