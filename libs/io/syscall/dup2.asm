; dup2(oldfd, newfd) -> rax = newfd or -errno
;
; Atomically make *newfd* refer to the same open file description
; as *oldfd*. If *newfd* was already open, dup2 closes it first —
; the whole "close then dup" sequence is a single kernel step so
; concurrent threads never observe an intermediate closed state.
;
; If *oldfd* == *newfd* and *oldfd* is a valid fd, dup2 is a
; no-op that succeeds without closing anything. Handy for
; libraries that want to normalize an fd number without knowing
; whether the caller already handed them the right one.
;
; Common uses:
;
;   * Redirect stdin / stdout / stderr in a child process before
;     execve: dup2(pipe_fd, 0), dup2(log_fd, 1), etc.
;   * Replace a socket connection with a freshly reconnected one
;     without exposing the fd number change to the rest of the
;     process.
;
; -EBADF if *oldfd* is not open; -EBUSY on Linux if the same
; fd is being simultaneously opened by another thread (a rare
; race that macOS resolves silently).

%include "syscall.inc"

default rel

global dup2

section .text

dup2:
    mov rax, SYS_dup2
    SYSCALL_NORM
    ret
