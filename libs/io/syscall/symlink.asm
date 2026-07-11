; symlink(target, linkpath) -> rax = 0 or -errno
;
; Create a symbolic link at *linkpath* whose stored target
; string is *target*. The target string is written verbatim —
; the kernel does not validate that the referenced path exists,
; is reachable, or is well-formed. Dangling symlinks are
; permitted.
;
; -EEXIST if *linkpath* already exists (of any type).

%include "syscall.inc"

default rel

global symlink

section .text

symlink:
    mov rax, SYS_symlink
    SYSCALL_NORM
    ret
