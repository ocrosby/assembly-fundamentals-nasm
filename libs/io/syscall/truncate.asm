; truncate(path, length) -> rax = 0 or -errno
;
; Set the file at *path* to exactly *length* bytes. Extending
; past the current EOF zero-fills the gap; shrinking discards
; the trailing bytes irrevocably. The fd position of any process
; that has *path* open is NOT adjusted — a later read may return
; less than expected or return 0 (EOF) sooner.
;
; -EACCES if the file is not writable, -EISDIR if *path* names
; a directory, -EFBIG if *length* exceeds the filesystem's
; per-file maximum.

%include "syscall.inc"

default rel

global truncate

section .text

truncate:
    mov rax, SYS_truncate
    SYSCALL_NORM
    ret
