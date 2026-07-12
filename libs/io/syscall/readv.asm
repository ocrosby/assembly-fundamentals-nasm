; readv(fd, iov, iovcnt) -> rax = bytes read, 0 (EOF), or -errno
;
; Scatter read — the kernel reads a contiguous stream of bytes
; off `fd` into the sequence of buffers described by the
; `iov` array, filling each iovec's buffer in order. When one
; iovec's buffer is full the kernel moves on to the next
; without a boundary in the underlying data — a stream of 100
; bytes read across two 60-byte iovecs would fill the first
; entirely and put 40 bytes in the second.
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
;   rax > 0         total bytes read across all iovecs
;   rax = 0         EOF (peer closed a socket, end of a
;                   regular file at requested offset)
;   rax < 0         negative errno
;
; Common uses:
;   * Peel a fixed-size header off a wire protocol and drop
;     the variable-size body in a separate buffer, with one
;     syscall.
;   * Read into pieces of an already-allocated data structure
;     without needing an intermediate contiguous buffer.
;
; Three arguments — SysV rdi/rsi/rdx already match the kernel
; ABI, no SYSCALL_ARG4 needed.

%include "syscall.inc"

default rel

global readv

section .text

readv:
    mov rax, SYS_readv
    SYSCALL_NORM
    ret
