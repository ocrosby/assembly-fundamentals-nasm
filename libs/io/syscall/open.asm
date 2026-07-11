; open(path, flags, mode) -> rax = fd or negative errno
;
; Opens the file at `path` (a NUL-terminated C string) with the
; given `flags` (O_RDONLY, O_WRONLY, O_RDWR, plus optional
; O_CREAT, O_TRUNC, O_APPEND, O_NONBLOCK, ...) and, when O_CREAT
; is set, the given `mode` (0644, 0600, ...). Returns a new file
; descriptor on success or a negative errno on failure. When
; O_CREAT is not set the `mode` argument is ignored by the
; kernel, so callers can pass 0.
;
; Modern code should prefer openat() with AT_FDCWD as the base
; directory — openat() is the fdcwd-scoped form and cannot race
; against a chdir in another thread. open() is provided here for
; consumer symmetry with the POSIX name callers already know.

%include "syscall.inc"

default rel

global open

section .text

open:
    mov rax, SYS_open
    SYSCALL_NORM
    ret
