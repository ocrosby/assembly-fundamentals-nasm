; fchownat(dirfd, path, uid, gid, flags) -> rax = 0 or -errno
;
; The dirfd-scoped counterpart to `chown`. As with `chown`,
; passing `-1` (all-ones `u32`) for either *uid* or *gid*
; means "keep this ID as-is" — a no-op that non-root callers
; can use to smoke-test the wrapper without needing
; privileges.
;
; The *flags* slot accepts AT_SYMLINK_NOFOLLOW; the default
; behavior (flags = 0) is to follow the terminal symlink and
; change the target's ownership. Both platforms honor this
; flag.
;
; Five arguments — SYSCALL_ARG4 handles the rcx→r10 shift for
; the 4th; the 5th (*flags*) already lives in r8 which matches
; the syscall ABI slot.

%include "syscall.inc"

default rel

global fchownat

section .text

fchownat:
    SYSCALL_ARG4
    mov rax, SYS_fchownat
    SYSCALL_NORM
    ret
