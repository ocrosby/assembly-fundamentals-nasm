; poll(fds, nfds, timeout) -> rax = ready count or negative errno
;
; Waits for events on `nfds` file descriptors described by an
; array of `struct pollfd` at `fds`. Each entry pairs an fd with
; requested events (POLLIN, POLLOUT, POLLERR, POLLHUP, …) and
; receives the observed events in `revents`. `timeout` is in
; milliseconds; -1 blocks indefinitely, 0 polls without blocking.
; Unlike select(), the caller does not need to know the numeric
; range of fds and the input is not clobbered on return.

%include "syscall.inc"

default rel

global poll

section .text

poll:
    mov rax, SYS_poll
    SYSCALL_NORM
    ret
