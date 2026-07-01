# macOS Syscall Reference

A category-organized list of the BSD system calls you are most likely to invoke
directly from x86-64 assembly on macOS. Each page carries the number to load
into `rax` alongside the argument layout, so you can drop a call straight into a
`syscall` sequence.

## How the number is formed

macOS encodes the **syscall class** in the high byte of `rax` and the call
number in the low bytes. The BSD/Unix class is class 2, which gives the prefix
`0x2000000`. The SDK header lists the *base* number for each call
(`SYS_write` is `4`); the value you load into `rax` is that base OR-ed with the
class prefix:

```text
rax = 0x2000000 | base       ; e.g. write: 0x2000000 | 4 = 0x2000004
```

Every table below shows both the decimal base and the ready-to-use `rax` value.

## Register convention

The `syscall` instruction takes its arguments in `rdi, rsi, rdx, r10, r8, r9`
and returns in `rax`, with a negative `rax` meaning `-errno`. That layout is the
same for every call here and is covered once in
[System Calls](../../16-system-calls.md); the tables below list only the per-call
argument roles.

## A caution before you use these

Apple discourages direct syscalls and may change or remove them between macOS
releases. The numbers here are correct for the current SDK, but they are not a
stable ABI. For anything beyond a learning exercise, link `libSystem` and call
`write`, `exit`, and friends as ordinary functions — see
[Linking](../../18-linking.md).

## Regenerating this list

Every number comes from the SDK header, not from memory:

```bash
grep '#define\s*SYS_' "$(xcrun --show-sdk-path)/usr/include/sys/syscall.h"
```

The header defines the full set (several hundred entries, many of them
Darwin-internal); the pages below curate the calls a programmer actually
reaches for.

## Categories

- [Process & execution](process.md) — `fork`, `execve`, `exit`, `wait4`, identity and process-group calls.
- [File descriptors & I/O](file-io.md) — `read`, `write`, `open`, `close`, `lseek`, `dup`, `fcntl`, `poll`.
- [Filesystem & metadata](filesystem.md) — `stat`, `rename`, `mkdir`, `link`, `chmod`, extended attributes.
- [Memory management](memory.md) — `mmap`, `munmap`, `mprotect`, `madvise`, shared memory.
- [Signals, time & resources](signals-time.md) — `sigaction`, `gettimeofday`, timers, `getrlimit`.
- [Sockets & networking](network.md) — `socket`, `connect`, `bind`, `accept`, send and receive.

## See also

- [System Calls](../../16-system-calls.md) — the register convention and the macOS-vs-Linux overview.
- [References](../../21-references.md) — external syscall tables and manuals.
- [Index](../../README.md)
