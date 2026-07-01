# Linux Syscall Reference (x86-64)

A category-organized list of the Linux system calls you are most likely to
invoke directly from x86-64 assembly. Each page carries the number to load into
`rax` alongside the argument layout, so you can drop a call straight into a
`syscall` sequence.

## How the number is used

Unlike macOS, Linux uses no class prefix: the syscall number goes **directly**
into `rax`.

```text
rax = number       ; e.g. write is 1, so: mov rax, 1
```

The numbers here are the **x86-64** table; other architectures assign different
numbers to the same names. Unlike macOS, the Linux syscall table is a stable
ABI — a number, once assigned, does not change.

## Register convention

The `syscall` instruction takes its arguments in `rdi, rsi, rdx, r10, r8, r9`
and returns in `rax`, with a negative `rax` meaning `-errno`. That layout is the
same for every call here and is covered once in
[System Calls](../../16-system-calls.md); the tables below list only the
per-call argument roles.

## Regenerating this list

The numbers come from the kernel's own table, not from memory:

```bash
# on a Linux host:
grep -E '^[0-9]+\s+common|^[0-9]+\s+64' /usr/include/asm/unistd_64.h
# or read the source of truth in the kernel tree:
#   arch/x86/entry/syscalls/syscall_64.tbl
```

## Categories

- [Process & execution](process.md) — `fork`, `clone`, `execve`, `exit`, `wait4`, identity and process-group calls.
- [File descriptors & I/O](file-io.md) — `read`, `write`, `open`, `openat`, `close`, `lseek`, `dup`, `fcntl`, `poll`.
- [Filesystem & metadata](filesystem.md) — `stat`, `rename`, `mkdir`, `link`, `chmod`, the `*at` variants, extended attributes.
- [Memory management](memory.md) — `brk`, `mmap`, `munmap`, `mprotect`, `madvise`.
- [Signals, time & resources](signals-time.md) — `rt_sigaction`, `nanosleep`, `clock_gettime`, `getrlimit`.
- [Sockets & networking](network.md) — `socket`, `connect`, `bind`, `accept`, send and receive.

## See also

- [System Calls](../../16-system-calls.md) — the register convention and the macOS-vs-Linux overview.
- [References](../../21-references.md) — external syscall tables and manuals.
- [Index](../../README.md)
