# NASM Fundamentals — Documentation

A progressive walkthrough of x86-64 assembly with NASM. Each guide is intentionally short so a single topic fits on one screen. Read in order, or jump to what you need.

## Getting Started

1. [Installation](01-installation.md) — verify the toolchain.
2. [Hello World](02-hello-world.md) — assemble, link, run.
3. [NASM Syntax](03-syntax.md) — labels, directives, comments.

## Core Concepts

4. [Registers](04-registers.md) — general-purpose, RIP, RFLAGS.
5. [Sections](05-sections.md) — `.text`, `.data`, `.bss`, `.rodata`.
6. [Data Types](06-data-types.md) — `db`, `dw`, `dd`, `dq`, `resb`.
7. [Addressing Modes](07-addressing-modes.md) — immediate, register, memory.

## Operations

8. [Data Movement](08-data-movement.md) — `mov`, `lea`, `xchg`, `push`, `pop`.
9. [Arithmetic](09-arithmetic.md) — `add`, `sub`, `imul`, `idiv`, `inc`, `dec`.
10. [Bitwise & Shifts](10-bitwise.md) — `and`, `or`, `xor`, `not`, `shl`, `shr`.
11. [Comparison & Flags](11-comparison.md) — `cmp`, `test`, RFLAGS bits.

## Control Flow

12. [Jumps](12-jumps.md) — unconditional and conditional branches.
13. [Loops](13-loops.md) — `loop`, counter idioms, `rep`.
14. [Procedures](14-procedures.md) — `call`, `ret`, the System V AMD64 ABI.
15. [The Stack](15-stack.md) — frames, locals, alignment.

## Going Further

16. [System Calls](16-system-calls.md) — macOS vs Linux conventions.
17. [Macros](17-macros.md) — `%define`, `%macro`, conditional assembly.
18. [Linking](18-linking.md) — `ld`, object files, entry points.
19. [Debugging](19-debugging.md) — `lldb` and `gdb` basics.
20. [Cheat Sheet](20-cheat-sheet.md) — x86-64 instructions and registers.

## Extended coverage

- [Floating Point](25-floating-point.md) — scalar single and double
  arithmetic on the SSE `xmm` registers, calling convention, and
  int↔float conversion.
- [Memory Mapping](26-memory-mapping.md) — `mmap` + `munmap` and the
  three useful flag combinations: anonymous private scratch,
  file-backed private view, and `MAP_SHARED` for IPC across `fork`.
- [Static Libraries](27-libraries.md) — the eight reusable NASM
  archives under `libs/` that later examples opt into: what they
  cover, the shared calling and error convention, the dependency
  graph, and how to link.
- [Signals](28-signals.md) — the POSIX signal model as libsig
  sees it: sigset bitmap layout, `SIG_BLOCK` / `SIG_UNBLOCK` /
  `SIG_SETMASK`, why `sigaction` is deferred, and how the
  block-mask pattern replaces "ignore this signal" until
  handler installation lands.
- [Processes](29-processes.md) — libproc's process-control
  model: `fork` returning twice, `execve` replacing the
  image, `wait4` status-word interpretation, and the
  `spawn_wait` composed helper.
- [File I/O](30-io.md) — libio's file family (`file_read_all`
  / `file_write_all` / `file_append` / `file_copy`), the
  O_TRUNC vs O_APPEND distinction, short-write handling, and
  the ownership contract for the mmap `file_read_all` returns.
- [Strings and byte buffers](31-str.md) — libstr's three
  families (raw-byte, NUL-terminated string, integer
  conversion), why every scan is byte-at-a-time, the
  `strcpy` contract and the `strncpy` non-decision, and
  `LLONG_MIN` handling in `itoa`.
- [Sockets and networking](32-sock.md) — libsock's Berkeley
  sockets primer: `struct sockaddr_in` layout and the
  `SIN_HEADER` macOS/Linux difference, byte-order helpers,
  the `send_all` short-write loop, and the
  `server_bind_listen` / `client_connect` composed helpers.
- [Time](33-time.md) — libtime's wall/CPU-clock story:
  `struct timeval` layout, `sleep_ms` via the `poll` trick,
  `getrusage`, `now_ms` / `time_diff_us` helpers, and the
  deliberate macOS asymmetry in `monotonic_ms`
  (Linux `CLOCK_MONOTONIC`, macOS `-ENOSYS`).
- [DNS resolution](34-resolv.md) — libresolv's three
  lookup layers (wire, transport, hostname), the RFC 1035
  header, UDP → TCP truncation retry, and the
  `/etc/resolv.conf` + `/etc/hosts` walk that mirrors
  POSIX `getaddrinfo`.
- [Multiplexing with poll](35-multiplexing.md) — the
  `struct pollfd` layout, timeout semantics, the events
  that matter (`POLLIN` / `POLLOUT` / `POLLHUP`), the
  three things poll does not tell you, and why libsock
  stops at poll rather than shipping `epoll` / `kqueue`
  wrappers.
- [File locking with flock](36-file-locking.md) — the
  three operations plus `LOCK_NB`, the advisory-vs-
  mandatory distinction, why the per-open-file-
  description scope makes `flock` the safer default over
  `fcntl` POSIX locks, and non-blocking acquisition.
- [Non-blocking I/O](37-nonblocking.md) — what
  `O_NONBLOCK` does to `read` / `write` / `accept` /
  `connect`, the `F_GETFL` / `F_SETFL` read-modify-write
  dance, why `-EAGAIN` is the whole point, and how
  non-blocking + `poll` becomes an event loop.

## Appendix

- [References](21-references.md) — external manuals, instruction-set references, and syscall tables.
- [NASM Cheat Sheet](22-nasm-cheat-sheet.md) — assembler-specific syntax: directives, preprocessor, storage sizes, literals.
- [lldb Walkthrough](23-lldb-walkthrough.md) — step-by-step debugging of `examples/14-square` on macOS.
- [gdb Walkthrough](24-gdb-walkthrough.md) — same walkthrough, on Linux.
- [Syscall Reference](syscalls/README.md) — the common macOS and Linux syscalls, organized by category, with the `rax` value each one needs.
- [Runnable examples](../examples/) — a constructive sequence of nine small programs paired with chapters 2, 9, 13, 14, 15, and 17.

## Conventions Used in These Guides

- Examples target **x86-64** (long mode), **Intel syntax** (NASM default).
- Platform differences are called out under **macOS** and **Linux** subheadings.
- Code is given as it would be saved in a `.asm` file; assemble with `nasm` and link with `ld` as shown in [Hello World](02-hello-world.md).
