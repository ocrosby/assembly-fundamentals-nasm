; readlinkat(dirfd, path, buf, bufsize) -> rax = bytes copied or -errno
;
; The dirfd-scoped counterpart to `readlink`. Same
; not-NUL-terminated write contract — the caller detects
; truncation by comparing the return value against *bufsize*
; and appends its own terminator if it needs a C-string.
;
; Takes four arguments; SYSCALL_ARG4 shifts *bufsize* from rcx
; into r10 before the syscall.

%include "syscall.inc"

default rel

global readlinkat

section .text

readlinkat:
    SYSCALL_ARG4
    mov rax, SYS_readlinkat
    SYSCALL_NORM
    ret
