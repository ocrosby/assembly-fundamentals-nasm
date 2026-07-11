; munmap(addr, length) -> rax = 0 or -errno
;
; Release a mapping previously created by mmap. The address
; range `[addr, addr+length)` is unmapped from the calling
; process's virtual address space; subsequent accesses to any
; page in that range produce SIGSEGV until the space is
; remapped.
;
; Arguments:
;   rdi = addr    starting address, must be page-aligned.
;                 Passing an address that was not returned by
;                 a prior mmap is legal — the kernel unmaps
;                 whatever mappings intersect the range —
;                 but is a common way to accidentally free
;                 someone else's memory.
;   rsi = length  bytes to unmap. Rounded up to a page
;                 boundary. Zero is invalid.
;
; Return:
;   rax = 0        success (even if the range contained no
;                  mappings — munmap is idempotent on empty
;                  ranges)
;   rax = -EINVAL  addr not page-aligned or length is zero
;
; Two arguments — plain SysV rdi/rsi match the kernel ABI, no
; SYSCALL_ARG4 rewrite needed. The wrapper is a straight
; SYSCALL_NORM pass-through.
;
; Common pattern: pair munmap with the *exact* addr and length
; that mmap returned. Storing both values in a caller-side
; struct is cheaper than trying to recover them later.

%include "syscall.inc"

default rel

global munmap

section .text

munmap:
    mov rax, SYS_munmap
    SYSCALL_NORM
    ret
