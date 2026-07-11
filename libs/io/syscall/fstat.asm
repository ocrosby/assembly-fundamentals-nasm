; fstat(fd, statbuf) -> rax = 0 or -errno
;
; Populate a caller-supplied stat buffer with metadata about the
; open file at *fd*. The buffer must be at least STATBUF_SIZE
; (144) bytes and 8-byte aligned; libio's syscall.inc exports
; both STATBUF_SIZE and offsets for the fields callers most
; commonly need (starting with ST_SIZE_OFF in v1.1).
;
; The struct layouts differ between macOS `struct stat64` and
; Linux `struct stat` — same total width but different field
; ordering. Callers that touch fields other than st_size
; should either extend syscall.inc with the offsets they need
; or accept the platform dependency.
;
; This wrapper is thin: it forwards the two arguments straight
; to the kernel and normalizes the return via SYSCALL_NORM.

%include "syscall.inc"

default rel

global fstat

section .text

fstat:
    mov rax, SYS_fstat
    SYSCALL_NORM
    ret
