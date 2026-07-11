; flock(fd, operation) -> rax = 0 or -errno
;
; BSD advisory file locking. The lock is associated with the
; open file description, not the fd or the file — so `dup`
; and `fork` share a lock, but two independent `open` calls to
; the same file get independent locks.
;
; Operations (OR'd together where sensible):
;
;   LOCK_SH   shared lock — multiple readers can hold it
;   LOCK_EX   exclusive lock — only one holder at a time
;   LOCK_UN   release whatever lock this fd holds
;   LOCK_NB   non-blocking modifier: if the requested lock
;             cannot be acquired immediately, return
;             -EWOULDBLOCK (-35 macOS, -11 Linux) instead of
;             sleeping until it can
;
; Advisory means the kernel does not enforce the lock against
; unlocked accessors — every participating process must
; cooperatively check its lock state. That is fine for the
; common case (a single application coordinating between its
; own instances) but insufficient for security-sensitive
; workloads.
;
; Not portable across NFS in the way fcntl POSIX locks are;
; use fcntl-based locking (F_SETLK) if the file may live on a
; network filesystem.

%include "syscall.inc"

default rel

global flock

section .text

flock:
    mov rax, SYS_flock
    SYSCALL_NORM
    ret
