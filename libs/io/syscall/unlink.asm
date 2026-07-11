; unlink(path) -> rax = 0 or -errno
;
; Remove the directory entry at *path*. If the referenced file's
; link count drops to zero and no process has it open, the
; kernel reclaims the inode; otherwise the file lives until the
; last open handle closes.
;
; Symlinks are removed as themselves — the target is untouched.
; Directories cannot be removed via unlink; use rmdir for that
; (returns -EPERM / -EISDIR depending on platform).

%include "syscall.inc"

default rel

global unlink

section .text

unlink:
    mov rax, SYS_unlink
    SYSCALL_NORM
    ret
