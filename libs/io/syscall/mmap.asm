; mmap(addr, length, prot, flags, fd, offset) -> rax = addr or -errno
;
; Establish a new virtual-memory mapping in the calling process.
; The kernel returns the address the mapping was placed at
; (which may differ from `addr` unless MAP_FIXED is set), or a
; negative errno via the SYSCALL_NORM path if the mapping could
; not be created.
;
; Arguments:
;   rdi = addr    hint for where to place the mapping. Pass 0
;                 (or `NULL`) to let the kernel choose; the
;                 kernel usually ignores a non-NULL hint unless
;                 MAP_FIXED is also set in `flags`.
;   rsi = length  bytes to map. Rounded up to a page boundary
;                 (typically 4096 or 16384 on Apple Silicon,
;                 always a system-wide constant on a given
;                 kernel). Zero is invalid.
;   rdx = prot    OR-ed bitmask of PROT_NONE / PROT_READ /
;                 PROT_WRITE / PROT_EXEC. PROT_NONE creates
;                 a reserved-address hole that can be upgraded
;                 later with mprotect.
;   rcx = flags   OR-ed bitmask. Must include exactly one of
;                 MAP_SHARED or MAP_PRIVATE. Add MAP_ANON to
;                 request anonymous (zero-filled) memory —
;                 `fd` must then be -1 and `offset` 0.
;                 Add MAP_FIXED to force `addr` to be used
;                 exactly (a whole-page overwrite; existing
;                 mappings at the target are silently
;                 replaced).
;   r8  = fd      file descriptor to map from. Ignored for
;                 anonymous mappings (pass -1 by convention).
;   r9  = offset  byte offset within `fd` — must be a multiple
;                 of the page size. 0 for anonymous mappings.
;
; Return:
;   rax = address on success; negative errno on failure.
;         Common errors:
;           -ENOMEM   process address space or system memory
;                     exhausted
;           -EACCES   fd's open mode incompatible with prot
;                     (e.g. PROT_WRITE on an O_RDONLY fd)
;           -ENODEV   fd points to a filesystem that does not
;                     support mmap (some /proc / /sys entries)
;           -EINVAL   flags combination invalid (e.g. neither
;                     SHARED nor PRIVATE), length is 0, or
;                     offset is not page-aligned
;
; Six arguments — SYSCALL_ARG4 shifts the 4th (flags) from
; SysV `rcx` to syscall `r10`. `r8` and `r9` already match
; the kernel-side register slots.

%include "syscall.inc"

default rel

global mmap

section .text

mmap:
    SYSCALL_ARG4                    ; rcx → r10 (flags)
    mov rax, SYS_mmap
    SYSCALL_NORM
    ret
