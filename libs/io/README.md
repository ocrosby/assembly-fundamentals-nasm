# libs/io/

File-descriptor and filesystem primitives packaged as the static
archive `libio.a`. Every routine is a direct syscall wrapper (or,
in `util/`, a small helper composed of syscall wrappers) — no
libc, no libSystem call, no allocation. The archive covers the
syscall-backed portion of POSIX
[`<fcntl.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/fcntl.h.html)
and [`<unistd.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/unistd.h.html)
that a caller needs to open a file, seek within it, do positioned
reads and writes, stat it, and manipulate the surrounding
namespace — without libc's `FILE*` layer sitting in front.

`read`, `write`, and `close` are deliberately not exported here —
they already live in [`libsock.a`](../sock/) and are protocol-
neutral (both socket I/O and file I/O use them). A consumer that
wants file I/O links both archives; the two-archive rule is
called out in [`../README.md`](../README.md).

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Exported symbols

**v1.0 — file I/O core:**

| Symbol   | Arguments                                        | Returns                              |
| -------- | ------------------------------------------------ | ------------------------------------ |
| `open`   | `path`, `flags`, `mode`                          | fd or negative errno                 |
| `openat` | `dirfd`, `path`, `flags`, `mode`                 | fd or negative errno                 |
| `lseek`  | `fd`, `offset`, `whence` (SEEK_SET/CUR/END)      | new absolute offset or negative errno |
| `pread`  | `fd`, `buf`, `count`, `offset`                   | bytes read (0 = EOF) or -errno       |
| `pwrite` | `fd`, `buf`, `count`, `offset`                   | bytes written or negative errno      |

**v1.1 — metadata + namespace ops:**

| Symbol    | Arguments                        | Returns                       |
| --------- | -------------------------------- | ----------------------------- |
| `fstat`   | `fd`, `statbuf*`                 | `0` or negative errno         |
| `io_size` | `fd`, `out_size*`                | `0` or negative errno         |
| `unlink`  | `path`                           | `0` or negative errno         |
| `mkdir`   | `path`, `mode`                   | `0` or negative errno         |
| `rmdir`   | `path`                           | `0` or negative errno         |

`fstat` writes a caller-supplied stat buffer of size
`STATBUF_SIZE` (144 bytes on both platforms). The struct
layout differs — macOS uses `struct stat64`, Linux uses
`struct stat` — so callers that touch fields other than
`st_size` must either add named offsets to
[`syscall/syscall.inc`](syscall/syscall.inc) or accept the
platform dependency. `io_size` sidesteps this entirely for
the common case: it fstats the fd internally and writes the
file size to `out_size` as a signed 64-bit integer, hiding
the offset behind a portable API.

`unlink`, `mkdir`, and `rmdir` are thin syscall wrappers on
top of the kernel's namespace ops. `mkdir`'s mode is
filtered through the caller's umask, matching libc semantics;
`rmdir` requires the directory to be empty (returns
`-ENOTEMPTY` otherwise); `unlink` rejects directories with
`-EPERM` or `-EISDIR` depending on platform.

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
extern fstat, unlink, mkdir, rmdir      ; v1.1
extern io_size                          ; v1.1 (util helper)
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

- [`io-smoke.asm`](test/io-smoke.asm) — success path. Sub-checks
  `1..C` cover the v1.0 five wrappers on a real mktemp'd file
  (pwrite two halves, lseek `SEEK_END` for size, pread across
  the seam, openat + pread the tail). Sub-checks `D..K` add
  v1.1: `fstat` populates a stat buffer whose `st_size` at
  `ST_SIZE_OFF` reads `10`, `io_size` returns the same size
  portably, `mkdir` + `rmdir` round-trip a scratch dir,
  and `unlink` succeeds once then fails with `-ENOENT` the
  second time.
- [`fail-smoke.asm`](test/fail-smoke.asm) — failure path. Each
  wrapper is called with args the kernel is guaranteed to
  reject (`/proc/libio/does-not-exist-` → `-ENOENT` for
  `open`, `openat`, `unlink`, `mkdir`, `rmdir`; `fd=999999` →
  `-EBADF` for `lseek`, `pread`, `pwrite`, `fstat`). Exercises
  the macOS `SYSCALL_NORM` `neg rax` line on every export.
- [`c-smoke.c`](test/c-smoke.c) — verifies `libio.a` is linkable
  and callable from a normal C toolchain. Uses GCC `__asm__`
  labels to bind libio calls to their bare names (bypassing
  Mach-O's underscore convention). v1.1: also exercises the
  new `fstat`, `io_size`, `unlink`, `mkdir`, `rmdir` symbols
  end-to-end so a C consumer's link line is proven to work.

On success the runner prints one line per test:

```text
PASS: io-smoke     output=[PASS]
PASS: fail-smoke   output=[PASS]
PASS: c-smoke      output=[PASS]
```

Both platforms are exercised on CI.

## What is not here — yet

v1.1 closes the biggest v1 gaps (metadata via `fstat`, portable
size via `io_size`, and the namespace ops `unlink` / `mkdir` /
`rmdir`). Still deferred:

- `stat`, `lstat` — path-based stat variants. `fstat` covers
  most consumer needs once you have an open fd; a path-based
  variant is a straightforward wrapper if someone needs it.
- Directory iteration (`getdents64` on Linux, `getdirentries`
  on macOS). `struct dirent` layouts vary by platform and the
  syscall shape differs, so a portable helper is a larger
  design task.
- `rename`, `chmod`, `chown`, `symlink`, `readlink`,
  `truncate` — no consumer needs them yet.
- `dup`, `dup2`, `pipe` — fd-graph manipulation. Useful for
  process plumbing but out of scope for the file-oriented
  archive.

## Utility helpers

`util/` (added in v1.1) holds pure-computation helpers that
sit on top of one or more syscall wrappers. Currently:

- [`io_size`](util/io-size.asm) — calls `fstat` and extracts
  `st_size` at the platform-specific offset, storing the
  result in a caller-supplied `long*`. Removes the need for
  callers to know that `ST_SIZE_OFF` is `96` on macOS and
  `48` on Linux.

Future helpers that compose a common file-I/O pattern into
one call belong here rather than in `syscall/`.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`).
- [`../sock/`](../sock/) — Berkeley sockets syscall wrappers
  plus the `<arpa/inet.h>` byte-order and text helpers.
  Consumers of `libio.a` typically also link `libsock.a` for
  `read`, `write`, and `close`.
