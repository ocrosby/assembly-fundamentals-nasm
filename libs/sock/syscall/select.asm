; select(nfds, readfds, writefds, exceptfds, timeout) -> rax = ready count or -errno
;
; Waits until one or more of the fds tracked by three fd_set
; bitmaps is ready for reading, writing, or has an exceptional
; condition. `nfds` is one greater than the highest fd in any
; set. `timeout` points at a `struct timeval` (or NULL to block
; indefinitely); a zeroed timeval polls without blocking. On
; return, the fd_sets are modified in place to show which fds
; are ready.

%include "syscall.inc"

default rel

global select

section .text

select:
    SYSCALL_ARG4                    ; exceptfds: rcx -> r10
    mov rax, SYS_select
    SYSCALL_NORM
    ret
