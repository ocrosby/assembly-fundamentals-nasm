; openat(dirfd, path, flags, mode) -> rax = fd or negative errno
;
; The fd-relative form of open(). If `path` is absolute, `dirfd`
; is ignored. If `path` is relative, resolution starts at the
; directory referred to by `dirfd`. The special value
; AT_FDCWD (-2 on macOS and -100 on Linux) means "resolve
; relative to the current working directory" — the same
; behavior open() has, but without racing against a concurrent
; chdir.
;
; Takes four arguments, so SYSCALL_ARG4 moves the flags arg
; from rcx (SysV slot 4) into r10 (syscall slot 4) before the
; kernel entry.

%include "syscall.inc"

default rel

global openat

section .text

openat:
    SYSCALL_ARG4                    ; flags: rcx -> r10
    mov rax, SYS_openat
    SYSCALL_NORM
    ret
