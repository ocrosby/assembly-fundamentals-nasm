; read(fd, buf, len) -> rax = bytes read (0 = EOF) or negative errno
;
; Reads up to `len` bytes from `fd` into `buf`. A return value
; of 0 on a stream socket means the peer performed an orderly
; shutdown of its send half. Short reads are normal — callers
; loop until they have what they need, or hit rax == 0, or hit a
; negative errno.

%include "syscall.inc"

default rel

global read

section .text

read:
    mov rax, SYS_read
    SYSCALL_NORM
    ret
