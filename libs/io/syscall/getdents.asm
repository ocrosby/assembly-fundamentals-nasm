; getdents(fd, buf, count, position*) -> rax = bytes filled or -errno
;
; Portable directory read. Fills *buf* with a stream of
; variable-length dirent records that util/dir-iter walks. The
; wire format differs between platforms but the field offsets
; every consumer cares about (d_reclen, d_type, d_name) are
; exposed via syscall.inc's D_*_OFF constants.
;
; The *position* argument is used by macOS's getdirentries64
; syscall as an in-out cookie the caller uses to resume from a
; previous read position. Linux's getdents64 does not have that
; concept — the fd's own file position carries the state — so
; the argument is ignored on that side. Callers pass the same
; slot on both platforms and let it be zeroed once at
; dir_iter_open time.
;
; Return convention: positive = bytes written to *buf* (may be
; less than *count*), zero = end-of-directory, negative = errno.
;
; Takes four arguments; SYSCALL_ARG4 moves *position* from rcx
; to r10 before the macOS syscall. On Linux we still run the
; macro even though the 4th register slot is unused — it is
; harmless (r10 is caller-saved and unused elsewhere in this
; wrapper).

%include "syscall.inc"

default rel

global getdents

section .text

getdents:
    SYSCALL_ARG4
    mov rax, SYS_getdents
    SYSCALL_NORM
    ret
