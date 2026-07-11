; chown(path, uid, gid) -> rax = 0 or -errno
;
; Change the owning uid and gid of the file at *path*. A
; caller-supplied value of -1 (all ones in the u32) means
; "leave this ID as-is" — the same sentinel libc uses. That
; makes chown(path, -1, -1) a no-op that succeeds so long as
; the file exists and the caller has traversal permission,
; which is useful for smoke-testing the wrapper without
; privileges.
;
; Non-root callers get -EPERM for any change that would
; transfer ownership away from themselves.

%include "syscall.inc"

default rel

global chown

section .text

chown:
    mov rax, SYS_chown
    SYSCALL_NORM
    ret
