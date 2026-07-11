; fstatat(dirfd, path, statbuf, flags) -> rax = 0 or -errno
;
; The dirfd-scoped counterpart to `stat` (or `lstat`, when
; AT_SYMLINK_NOFOLLOW is passed in *flags*). Writes the same
; 144-byte struct as `fstat` / `stat` / `lstat`, with the
; same ST_SIZE_OFF etc. offsets.
;
; On macOS this wraps `fstatat64` (BSD syscall 470) — the
; 64-bit-inode variant, matching what fstat64 / stat64 /
; lstat64 return. The older `fstatat` (469) returns a struct
; with 32-bit inode fields at different offsets and is
; deliberately not exposed by libio.
;
; Takes four arguments; SYSCALL_ARG4 shifts *flags* from rcx
; into r10 before the syscall.

%include "syscall.inc"

default rel

global fstatat

section .text

fstatat:
    SYSCALL_ARG4
    mov rax, SYS_fstatat
    SYSCALL_NORM
    ret
