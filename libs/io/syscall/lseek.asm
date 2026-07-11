; lseek(fd, offset, whence) -> rax = new absolute offset or -errno
;
; Moves the file position of `fd` to `offset` bytes relative to
; `whence`: SEEK_SET (0) from the start of the file, SEEK_CUR (1)
; from the current position, SEEK_END (2) from the end. On
; success returns the new absolute offset in bytes; on failure
; returns a negative errno.
;
; A common pattern: `lseek(fd, 0, SEEK_END)` returns the file's
; size without opening a stat struct. Cheap and portable.

%include "syscall.inc"

default rel

global lseek

section .text

lseek:
    mov rax, SYS_lseek
    SYSCALL_NORM
    ret
