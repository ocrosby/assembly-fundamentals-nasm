; mkdirat(dirfd, path, mode) -> rax = 0 or -errno
;
; The dirfd-scoped counterpart to `mkdir`. Resolves *path*
; relative to *dirfd* (or to cwd when *dirfd* is AT_FDCWD).
; Same umask-filtered mode semantics as `mkdir`.

%include "syscall.inc"

default rel

global mkdirat

section .text

mkdirat:
    mov rax, SYS_mkdirat
    SYSCALL_NORM
    ret
