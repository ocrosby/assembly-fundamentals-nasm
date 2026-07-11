; chmod(path, mode) -> rax = 0 or -errno
;
; Change the permission bits of the file at *path*. Only the
; owner or a privileged process can succeed; other callers get
; -EPERM. The setuid / setgid / sticky bits (in the high
; portion of *mode*) obey the same rules as libc's chmod —
; POSIX allows the kernel to silently clear them if the caller
; is not privileged.

%include "syscall.inc"

default rel

global chmod

section .text

chmod:
    mov rax, SYS_chmod
    SYSCALL_NORM
    ret
