# libs/

Reusable NASM archives for the assembly-fundamentals-nasm repo. Each
subdirectory produces a single static archive (`.a`) that consumer
examples can link against. Archives here are **not part of the
constructive example sequence** in `examples/`; they exist as
infrastructure that later examples opt into.

All archives in this directory share the same conventions:

- **Direct syscalls only** — no `libc` / `libSystem` dependency.
  Consumer binaries link with a bare `ld` invocation; they do not
  need `-lSystem` or `-lc`, and callers do not have to honor the
  16-byte-alignment-before-`call` rule to invoke these routines.
- **System V AMD64 ABI** — arguments in `rdi`, `rsi`, `rdx`, `rcx`,
  `r8`, `r9`; return value in `rax`. Callee-saved registers
  (`rbx`, `rbp`, `r12`–`r15`) are preserved by every routine.
- **Uniform error convention** — routines that can fail return a
  negative `errno` in `rax` on failure and a non-negative value on
  success, on **both** platforms. The macOS BSD carry-flag error
  convention is normalized inside each library so callers see the
  Linux `-errno` shape everywhere.

## Archives

| Path              | Archive     | Purpose                                                                                        |
| ----------------- | ----------- | ---------------------------------------------------------------------------------------------- |
| [`asm/`](asm/)    | `libasm.a`  | Formatting and process helpers (`print_string`, `print_int`, `sys_exit`).                      |
| [`sock/`](sock/)  | `libsock.a` | Berkeley sockets syscall wrappers plus `<arpa/inet.h>` byte-order and IPv4/IPv6 text helpers.  |
| [`io/`](io/)      | `libio.a`   | File-descriptor primitives from `<fcntl.h>` / `<unistd.h>` (`open`, `openat`, `lseek`, `pread`, `pwrite`), plus stat/mkdir/*at, fcntl, flock, and mmap/munmap. |
| [`resolv/`](resolv/) | `libresolv.a` | DNS A-record resolver over UDP. Wire encode / decode plus a `resolv_a(name, resolver, port, out_ip)` entry point built on `libsock`, and a `resolv_sockaddr` composed helper that returns a filled `struct sockaddr_in`. |
| [`time/`](time/)  | `libtime.a` | Wall-clock and CPU-time primitives from `<sys/time.h>` / `<sys/resource.h>` — `gettimeofday`, `sleep_ms`, `getrusage`, plus a `time_diff_us` pure-computation helper. Nanosecond-precision monotonic time deferred; the macOS path is blocked without libSystem. |
| [`proc/`](proc/)  | `libproc.a` | Process control from `<unistd.h>` / `<sys/wait.h>` / `<signal.h>` — `fork`, `execve`, `wait4`, `getpid`, `getppid`, `kill`, plus a `spawn_wait` composed helper. |

Each subdirectory's `README.md` documents the exported symbols and
calling conventions for that archive.

## Building

Each archive is built independently:

```bash
make -C libs/asm
make -C libs/sock
make -C libs/io
make -C libs/resolv
make -C libs/time
make -C libs/proc
```

There is no aggregate `libs/Makefile` yet — each archive has its own
test suite and its own dependency graph (`libresolv` builds `libsock`
as a prerequisite; the others are independent).

## Linking against multiple archives

Consumer binaries list every archive they use on the `ld` command
line. Static-archive linkers scan left-to-right for unresolved
symbols, so the archive containing the *references* must appear
before the archive containing the *definitions*. When a future
`libhttp.a` calls into `libsock.a`, for instance:

```
ld ... consumer.o libhttp.a libsock.a -o consumer
```

When both archives are independent — as `libasm.a` and `libsock.a` are
today — the order does not matter.

A consumer that needs both file I/O and socket I/O lists `libio.a`
alongside `libsock.a`. `libio` deliberately does not export `read`,
`write`, or `close` — those live in `libsock` and are protocol-neutral,
so both file and socket callers reach into the same objects rather
than into duplicate definitions:

```
ld ... consumer.o libio.a libsock.a -o consumer
```

## Platform notes

macOS is the primary target for this repository — see
[`.claude/rules/platform-priority.md`](../.claude/rules/platform-priority.md).
Both platforms are supported; a change that works on macOS but breaks
the Linux ELF path is a regression.
