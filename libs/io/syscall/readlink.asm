; readlink(path, buf, bufsize) -> rax = bytes copied or -errno
;
; Copy the target string of the symlink at *path* into *buf*.
; Up to *bufsize* bytes are written; if the target is longer,
; the copy is truncated silently — the caller detects this by
; comparing the return value against *bufsize*. The buffer is
; NOT NUL-terminated; callers that want a C-string must do that
; themselves.
;
; -EINVAL if *path* is not a symbolic link.

%include "syscall.inc"

default rel

global readlink

section .text

readlink:
    mov rax, SYS_readlink
    SYSCALL_NORM
    ret
