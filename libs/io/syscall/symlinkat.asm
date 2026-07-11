; symlinkat(target, newdirfd, linkpath) -> rax = 0 or -errno
;
; Create a symbolic link at *linkpath* (resolved relative to
; *newdirfd*) whose stored target string is *target*. As with
; `symlink`, the target string is written verbatim — the
; kernel never validates that it names an existing file, so
; dangling links are legal.
;
; The argument order — target first, then dirfd + linkpath —
; mirrors the non-`at()` `symlink`. The dirfd applies only to
; the destination, not the target.

%include "syscall.inc"

default rel

global symlinkat

section .text

symlinkat:
    mov rax, SYS_symlinkat
    SYSCALL_NORM
    ret
