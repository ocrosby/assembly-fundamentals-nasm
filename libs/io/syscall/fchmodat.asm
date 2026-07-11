; fchmodat(dirfd, path, mode, flags) -> rax = 0 or -errno
;
; The dirfd-scoped counterpart to `chmod`. Resolves *path*
; relative to *dirfd* (or to cwd when *dirfd* is AT_FDCWD).
; Same permission-bit semantics as `chmod` — the caller must
; own the file or be privileged; setuid/setgid/sticky bits
; obey the same platform-specific rules.
;
; The *flags* argument accepts AT_SYMLINK_NOFOLLOW to affect
; the link itself when the terminal component is a symlink,
; though POSIX allows implementations to return -EOPNOTSUPP
; here; Linux does, macOS does not.
;
; Takes four arguments; SYSCALL_ARG4 shifts *flags* from rcx
; into r10 before the syscall.

%include "syscall.inc"

default rel

global fchmodat

section .text

fchmodat:
    SYSCALL_ARG4
    mov rax, SYS_fchmodat
    SYSCALL_NORM
    ret
