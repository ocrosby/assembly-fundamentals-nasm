; writev(fd, iov, iovcnt) -> rax = bytes written or -errno
;
; Gather write — the kernel concatenates the buffers described
; by the `iov` array into a single output stream and writes
; them to `fd`. To the reader on the other end this looks
; identical to a single `write` of the same total length; the
; iovec boundary is invisible.
;
; Arguments:
;   rdi = fd        file descriptor
;   rsi = iov*      pointer to an array of `struct iovec`.
;                   Each entry is 16 bytes:
;                     +0  void  *iov_base
;                     +8  size_t iov_len
;   rdx = iovcnt    number of entries in the array. Kernels
;                   cap this at IOV_MAX (16 on Darwin, 1024 on
;                   Linux); over-sized calls return -EINVAL.
;
; Return:
;   rax >= 0        total bytes written across all iovecs.
;                   Like `write`, a short return is legal —
;                   callers who want a strict "all bytes sent"
;                   contract should loop, or use libsock's
;                   `send_all` if the fd is a socket.
;   rax  < 0        negative errno
;
; Common uses:
;   * Send a fixed-size length prefix + a variable-length
;     payload in a single syscall, avoiding both an
;     intermediate copy and two round trips through the
;     kernel-user boundary.
;   * Emit a formatted log line assembled from prefix, level
;     name, and body without concatenating them into one
;     buffer first.
;
; Three arguments — SysV rdi/rsi/rdx already match the kernel
; ABI, no SYSCALL_ARG4 needed.

%include "syscall.inc"

default rel

global writev

section .text

writev:
    mov rax, SYS_writev
    SYSCALL_NORM
    ret
