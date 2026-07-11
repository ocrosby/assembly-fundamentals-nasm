; dup(oldfd) -> rax = new_fd or -errno
;
; Allocate the lowest-numbered free fd and point it at the same
; open file description as *oldfd*. Reads / writes through the
; new fd share every attribute of the underlying file with the
; original — position, mode, `O_APPEND` / `O_NONBLOCK` flags,
; the works. Only the fd-level flags (close-on-exec) start
; fresh: `dup`'s returned fd never has `FD_CLOEXEC` set.
;
; Common uses:
;
;   * Save an fd before `dup2`-ing over it, then restore later.
;   * Hand a socket to a subsystem that closes its arg while the
;     caller still needs the original open.
;
; -EBADF if *oldfd* is not a valid open descriptor;
; -EMFILE if the process has hit its fd limit.

%include "syscall.inc"

default rel

global dup

section .text

dup:
    mov rax, SYS_dup
    SYSCALL_NORM
    ret
