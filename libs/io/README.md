# libs/io/

File-descriptor and filesystem primitives packaged as the static
archive `libio.a`. Every routine is a direct syscall wrapper —
no libc, no libSystem call, no allocation. The archive covers
the syscall-backed portion of POSIX
[`<fcntl.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/fcntl.h.html)
and [`<unistd.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/unistd.h.html)
that a caller needs to open a file, seek within it, and do
positioned reads and writes without libc's `FILE*` layer sitting
in front.

`read`, `write`, and `close` are deliberately not exported here —
they already live in [`libsock.a`](../sock/) and are protocol-
neutral (both socket I/O and file I/O use them). A consumer that
wants file I/O links both archives; the two-archive rule is
called out in [`../README.md`](../README.md).

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Exported symbols

| Symbol   | Arguments                                        | Returns                              |
| -------- | ------------------------------------------------ | ------------------------------------ |
| `open`   | `path`, `flags`, `mode`                          | fd or negative errno                 |
| `openat` | `dirfd`, `path`, `flags`, `mode`                 | fd or negative errno                 |
| `lseek`  | `fd`, `offset`, `whence` (SEEK_SET/CUR/END)      | new absolute offset or negative errno |
| `pread`  | `fd`, `buf`, `count`, `offset`                   | bytes read (0 = EOF) or -errno       |
| `pwrite` | `fd`, `buf`, `count`, `offset`                   | bytes written or negative errno      |

`openat` takes a `dirfd` argument that scopes relative-path
resolution to a directory referred to by an fd. The special
value `AT_FDCWD` (`-2` on macOS, `-100` on Linux) means "resolve
relative to the current working directory" — the same behavior
`open()` has, without racing against a concurrent `chdir()`.
Prefer `openat` in new code.

`lseek` returning the new offset is useful even when the seek
result is not the point: `lseek(fd, 0, SEEK_END)` reports the
file's size without opening a stat struct.

`pread` / `pwrite` are positioned I/O. They neither consult nor
modify the fd's own file position, so they compose with the
seek-cursor form without interfering. Random-access parsers
benefit from this — a DNS `/etc/resolv.conf` reader, for
example, can hold the fd at a stable position while pread'ing
individual lines.

## Calling convention notes

The [shared `libs/` conventions](../README.md) apply: System V
AMD64 ABI, callee-saved `rbx` / `rbp` / `r12`–`r15`, uniform
non-negative-on-success / negative-errno-on-failure contract.
Two syscall-side subtleties on top of that — moving the SysV
4th argument from `rcx` into the syscall ABI slot `r10`, and
normalizing macOS's carry-flag error convention to Linux's
`-errno` shape — live inside the wrappers themselves. See
[`syscall/syscall.inc`](syscall/syscall.inc) for the
`SYSCALL_ARG4` and `SYSCALL_NORM` macros that implement them,
and libsock's [`syscall/README.md`](../sock/syscall/README.md)
for the full explanation the pattern was documented in first.

## Build

### macOS

```bash
make                                # produces libs/io/libio.a
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the object files into
`libio.a` with `ar rcs`.

### Linux

```bash
make                                # produces libs/io/libio.a
```

On Linux the same `make` assembles with `nasm -f elf64`.

## Linking against `libio.a`

In the consumer's `.asm`:

```nasm
extern open, openat, lseek, pread, pwrite
```

In the consumer's `Makefile`, append the archive to the link
line. For a consumer at `examples/NN-slug/`, the path is
`../../libs/io/libio.a`:

```makefile
LIBIO := ../../libs/io/libio.a

$(BIN): $(OBJ) $(LIBIO)
	$(LD) $(OBJ) $(LIBIO) -o $(BIN)
```

Consumers that also want `read`, `write`, and `close` — which
they almost always do — list `libsock.a` before `libio.a` on
the link line. Static-archive resolution is left-to-right, so
`libsock` is picked up first for its symbols and `libio` for
what it uniquely provides.

Building the consumer does not automatically build the archive;
run `make -C ../../libs/io` first.

## Test

```bash
make test
```

`make test` builds `libio.a` and runs three smoke tests via the
harness in [`test/`](test/):

- [`io-smoke.asm`](test/io-smoke.asm) — success path. Opens a
  temp file created by `mktemp` (path injected via
  `-DTMPFILE=...`), pwrites `"hello"` at offset 0 and
  `"world"` at offset 5, checks the file size via
  `lseek(SEEK_END)`, pread's a substring across the seam, then
  reopens via `openat(AT_FDCWD, …)` and pread's the tail.
  Covers each of the five wrappers on a real file.
- [`fail-smoke.asm`](test/fail-smoke.asm) — failure path. Each
  wrapper is called with args the kernel is guaranteed to
  reject (`/proc/libio/does-not-exist-` → `-ENOENT` for
  `open` and `openat`; `fd=999999` → `-EBADF` for `lseek`,
  `pread`, `pwrite`). Exercises the macOS `SYSCALL_NORM`
  `neg rax` line on every one of the five exports.
- [`c-smoke.c`](test/c-smoke.c) — verifies `libio.a` is linkable
  and callable from a normal C toolchain. Uses GCC `__asm__`
  labels to bind libio calls to their bare names (bypassing
  Mach-O's underscore convention) and lets `close`/`unlink`
  resolve to libc's underscored variants. If the archive ever
  breaks for C consumers this test catches it before an example
  does.

On success the runner prints one line per test:

```text
PASS: io-smoke     output=[PASS]
PASS: fail-smoke   output=[PASS]
PASS: c-smoke      output=[PASS]
```

Both platforms are exercised on CI.

## What is not here

For `libio` v1 the surface is deliberately small — the archive
exists to unblock libresolv reading `/etc/resolv.conf` and
`/etc/hosts`, not to be a comprehensive filesystem library.
Missing from this release:

- `stat`, `fstat`, `lstat` — the `struct stat` layout differs
  between Darwin and Linux, and every field access needs an
  `%ifdef` in NASM. Landing this requires a portable
  field-offset story, which is scope for v1.1.
- Directory iteration (`getdents64` on Linux, `getdirentries`
  on macOS). Same portability story as `stat`, plus a `struct
  dirent` layout that varies by platform. Deferred.
- Filesystem mutation (`unlink`, `rename`, `mkdir`, `rmdir`,
  `chmod`, `chown`, `symlink`, `readlink`, `truncate`). None
  needed for libresolv; adding them requires designing
  cross-platform argument handling that is not urgent.
- `dup`, `dup2`, `pipe` — fd-graph manipulation. Useful for
  process plumbing but out of scope for the initial file-open
  surface.

Each of these is a candidate for v1.1 or a follow-up archive
when a real consumer needs it.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`).
- [`../sock/`](../sock/) — Berkeley sockets syscall wrappers
  plus the `<arpa/inet.h>` byte-order and text helpers.
  Consumers of `libio.a` typically also link `libsock.a` for
  `read`, `write`, and `close`.
