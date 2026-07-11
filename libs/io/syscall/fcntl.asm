; fcntl(fd, cmd, arg) -> rax = command-specific value or -errno
;
; File-descriptor and file-status flag mutation. libc's fcntl is
; variadic — the third argument's meaning depends on *cmd*:
;
;   F_GETFD               arg is ignored; returns FD flags (u32).
;   F_SETFD  arg=flags    sets FD flags; returns 0.
;   F_GETFL               arg is ignored; returns file status
;                         flags (bits like O_APPEND, O_NONBLOCK,
;                         plus the fd's access mode in the low
;                         two bits).
;   F_SETFL  arg=flags    sets file status flags. Note: only
;                         O_APPEND, O_NONBLOCK, O_ASYNC and
;                         O_DIRECT can be changed after open;
;                         other bits are silently ignored.
;   F_DUPFD  arg=hint     dup into the lowest free fd >= hint;
;                         returns the new fd. The result never
;                         has FD_CLOEXEC set.
;
; libio's wrapper is a straight pass-through. Callers set the
; correct type of *arg* based on *cmd* and interpret the return
; value accordingly. See syscall.inc for the F_* / FD_* /
; O_NONBLOCK / O_APPEND constants a NASM caller needs.
;
; Common ways to combine with libio's other wrappers:
;
;   * Make a socket non-blocking:
;         flags = fcntl(fd, F_GETFL, 0)
;         fcntl(fd, F_SETFL, flags | O_NONBLOCK)
;   * Ensure a file survives exec:
;         fcntl(fd, F_SETFD, 0)   ; clear FD_CLOEXEC
;   * Ensure a file does NOT survive exec:
;         fcntl(fd, F_SETFD, FD_CLOEXEC)
;
; Three arguments — SysV register slots rdi/rsi/rdx already
; match the syscall ABI so no SYSCALL_ARG4 rewrite is needed.

%include "syscall.inc"

default rel

global fcntl

section .text

fcntl:
    mov rax, SYS_fcntl
    SYSCALL_NORM
    ret
