# Static Libraries

Once you have written the same `sys_write` boilerplate three times, the
answer is not to type it a fourth. This repo ships a set of reusable
NASM archives under [`libs/`](../libs/) that later examples opt into.
Each archive is one `.a` file, each routine is a direct syscall or a
small helper built on top of one, and none of them link libc.

## What is in `libs/`

Nine archives cover the routines this material builds on:

| Archive       | Purpose                                                                          |
| ------------- | -------------------------------------------------------------------------------- |
| `libasm.a`    | Formatting and process helpers (`print_string`, `print_int`, `sys_exit`, `panic`). |
| `libsock.a`   | Berkeley sockets, `<arpa/inet.h>` byte-order and text helpers, plus `send_all`.  |
| `libio.a`     | File-descriptor primitives (`open`, `lseek`, `pread`/`pwrite`, `mmap`, `readv`, …) and composed helpers (`file_copy`, `file_read_all`). |
| `libresolv.a` | DNS A-record resolver over UDP: wire encode/decode plus `resolv_a`, `resolv_dial`. |
| `libtime.a`   | `gettimeofday`, `sleep_ms`, `getrusage`, plus `now_ms` and `monotonic_ms`.        |
| `libproc.a`   | Process control (`fork`, `execve`, `wait4`, `kill`) plus the `spawn_wait` helper. |
| `libstr.a`    | Byte-manipulation helpers (`memcpy`, `memcmp`, `strlen`, `strchr`, `strcpy`, …). |
| `libsig.a`    | POSIX signal-mask primitives (`sigprocmask`, `sigpending`) plus sigset helpers.  |
| `libbuf.a`    | Mmap-backed growable byte buffer — `buf_init`, `buf_reserve`, `buf_append`, `buf_reset`, `buf_free` around a 24-byte `struct buf`. See [39-growable-buffer.md](39-growable-buffer.md). |

Each archive has its own `README.md` with the full symbol table and
per-platform notes.

## Shared conventions

Every archive honors the same three rules, so callers do not have to
switch mental models between them.

- **Direct syscalls only.** No libc, no libSystem. Consumers link with
  a bare `ld` invocation and do not have to honor the 16-byte-align
  rule before `call` that libc expects.
- **System V AMD64 ABI.** Arguments in `rdi`, `rsi`, `rdx`, `rcx`,
  `r8`, `r9`; return in `rax`. Callee-saved registers (`rbx`, `rbp`,
  `r12`–`r15`) are preserved.
- **Uniform error return.** A routine that can fail returns a
  negative `errno` in `rax` on failure and a non-negative value on
  success — on **both** platforms. macOS's carry-flag error
  convention is normalized inside each archive so callers only ever
  see the `-errno` shape.

## Dependency graph

Most archives are independent. Two edges exist today:

```
libresolv → libsock
libresolv → libio     (via libsock's shared read/write/close)
```

`libio` deliberately does not export `read`, `write`, or `close` —
those live in `libsock` and are protocol-neutral, so file and socket
callers reach into the same objects rather than into duplicate
definitions.

## Linking against multiple archives

Static-archive linkers scan left to right, so archives with
**references** appear before archives with **definitions**. When both
are independent — like `libasm.a` and `libio.a` — the order does not
matter. The `Makefile` in every example that uses `libs/` sets the
right `LIBS := ...` line already.

## Building

Each archive is built independently and has its own `test` target:

```bash
make -C libs/io          # produces libs/io/libio.a
make -C libs/io test     # runs the smoke suite
```

## See also

- [`libs/README.md`](../libs/README.md) — the archive index with more
  detail on the dependency graph and linking rules.
- [`examples/24-static-link`](../examples/24-static-link/) — the
  first example that links an archive from `libs/`.
- [`examples/37-config-load`](../examples/37-config-load/) — the
  first example that uses two archives on the same buffer.

## Next

- Back to [docs/README.md](README.md).
