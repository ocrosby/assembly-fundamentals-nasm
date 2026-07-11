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

**v1.2 — path-based stat + atomic rename:**

| Symbol   | Arguments                        | Returns                       |
| -------- | -------------------------------- | ----------------------------- |
| `stat`   | `path`, `statbuf*`               | `0` or negative errno         |
| `rename` | `oldpath`, `newpath`             | `0` or negative errno         |

**v1.3 — permission, symlink, truncation:**

| Symbol      | Arguments                      | Returns                              |
| ----------- | ------------------------------ | ------------------------------------ |
| `lstat`     | `path`, `statbuf*`             | `0` or negative errno                |
| `chmod`     | `path`, `mode`                 | `0` or negative errno                |
| `chown`     | `path`, `uid`, `gid`           | `0` or negative errno                |
| `symlink`   | `target`, `linkpath`           | `0` or negative errno                |
| `readlink`  | `path`, `buf*`, `bufsize`      | bytes copied or negative errno       |
| `truncate`  | `path`, `length`               | `0` or negative errno                |
| `ftruncate` | `fd`, `length`                 | `0` or negative errno                |

**v1.4 — directory iteration (portable):**

| Symbol           | Arguments                                          | Returns                                    |
| ---------------- | -------------------------------------------------- | ------------------------------------------ |
| `getdents`       | `fd`, `buf*`, `count`, `position*`                 | bytes filled, `0` at end, or negative errno |
| `dir_iter_open`  | `iter*`, `path`                                    | `0` or negative errno                      |
| `dir_iter_next`  | `iter*`, `name_buf*`, `bufsize`, `type_out*`       | `1` on entry, `0` at end, negative errno   |
| `dir_iter_close` | `iter*`                                            | `0` or negative errno                      |

**v1.5 — the `*at()` family (scoped path resolution):**

| Symbol       | Arguments                                                    | Returns                              |
| ------------ | ------------------------------------------------------------ | ------------------------------------ |
| `unlinkat`   | `dirfd`, `path`, `flags`                                     | `0` or negative errno                |
| `mkdirat`    | `dirfd`, `path`, `mode`                                      | `0` or negative errno                |
| `renameat`   | `olddirfd`, `oldpath`, `newdirfd`, `newpath`                 | `0` or negative errno                |
| `fstatat`    | `dirfd`, `path`, `statbuf*`, `flags`                         | `0` or negative errno                |
| `symlinkat`  | `target`, `newdirfd`, `linkpath`                             | `0` or negative errno                |
| `linkat`     | `olddirfd`, `oldpath`, `newdirfd`, `newpath`, `flags`        | `0` or negative errno                |
| `readlinkat` | `dirfd`, `path`, `buf*`, `bufsize`                           | bytes copied or negative errno       |

**v1.6 — permission and ownership `*at()` variants:**

| Symbol     | Arguments                                                    | Returns                              |
| ---------- | ------------------------------------------------------------ | ------------------------------------ |
| `fchmodat` | `dirfd`, `path`, `mode`, `flags`                             | `0` or negative errno                |
| `fchownat` | `dirfd`, `path`, `uid`, `gid`, `flags`                       | `0` or negative errno                |

`fchmodat` and `fchownat` are the dirfd-scoped counterparts to
`chmod` (v1.3) and `chown` (v1.3). Same semantics — the mode
bits go through the umask, the `-1` sentinel for uid/gid means
"leave that ID as-is", `AT_SYMLINK_NOFOLLOW` in the `flags`
slot targets the link itself when the terminal path component
is a symlink. Non-root callers can smoke-test the wrappers
with `fchownat(dirfd, path, -1, -1, 0)` which is a portable
no-op.

`utimensat` is deliberately NOT wrapped. macOS does not expose
a numbered `utimensat` syscall — its libc implements it in
userspace on top of `setattrlistat` + a bespoke `struct
attrlist`. That is fundamentally a different shape than a thin
syscall wrapper. Callers that need timestamp control on macOS
should reach for `SYS_utimes` / `SYS_futimes` (BSD syscalls
138 / 139) directly for now; if a real consumer materializes,
libio will grow a portable `touch(path)` helper that dispatches
appropriately per platform.

The `*at()` family resolves the *path* argument relative to
*dirfd* — a file descriptor pointing at a directory obtained
via `open` or `openat`. The special sentinel `AT_FDCWD` (`-2`
on macOS, `-100` on Linux; exported by `syscall.inc`) means
"resolve relative to the current working directory", so
`unlinkat(AT_FDCWD, path, 0)` is semantically identical to
`unlink(path)`.

Two useful flags are exported for the `flags` slots:

- **`AT_REMOVEDIR`** turns `unlinkat` into `rmdirat` — the
  entry must be an empty directory. Same value semantics as
  Linux/glibc.
- **`AT_SYMLINK_NOFOLLOW`** makes `fstatat` behave like
  `lstat` when the terminal component is a symlink.

`fstatat` on macOS wraps `fstatat64` (BSD syscall 470), the
64-bit-inode variant that matches the `stat64` / `fstat64` /
`lstat64` field layout the v1.1 / v1.2 / v1.3 wrappers use.
Callers can plug any of the four stat symbols in and expect
`ST_SIZE_OFF` and its neighbors to work uniformly.

`linkat` creates a **hard** link — a second directory entry
pointing at the same inode. Cross-filesystem hard links
fail with `-EXDEV`; hard-linking a directory fails with
`-EPERM` on both platforms regardless of privileges.

`symlinkat`'s argument order — target first, then
`newdirfd` + `linkpath` — mirrors POSIX `symlink`. The
`dirfd` slot applies only to the destination, not to the
target string (which is stored verbatim as always).

Directory iteration is where the two platforms diverge most —
Linux's `getdents64` (syscall 217) and macOS's
`getdirentries64` (BSD syscall 344) return the same raw-byte
stream shape but the `d_type` and `d_name` offsets inside each
record differ. `getdents` is a thin wrapper that hides only
the syscall number difference. `dir_iter_*` (in `util/`) hide
the record layout entirely.

The iterator uses a caller-allocated **opaque state block** of
`DIR_ITER_SIZE` (4128) bytes — includes the fd, refill
position, and a 4096-byte scratch buffer. NASM callers
`resb DIR_ITER_SIZE`; C callers reserve `unsigned char
iter[4128]`. No heap dependency, no hidden globals.

`dir_iter_next`'s three-valued return (`1` = have entry, `0`
= end of directory, negative = errno) fits the archive's
"non-negative on success" convention while making
end-of-directory a first-class value rather than a special
errno. `d_type` is written to `*type_out` as one of the
`DT_*` constants — same values on both platforms, exported by
`syscall.inc`.

`lstat` is `stat`'s "don't follow the terminal symlink"
variant. The struct layout matches `stat` / `fstat` — same
`ST_SIZE_OFF` etc. — so a caller that already knows the
constants can plug `lstat` in without any other change.

`chown` accepts `-1` (all-ones `u32`) for either `uid` or
`gid` as "keep existing". `chown(path, -1, -1)` is therefore
a safe no-op that non-root callers can use to smoke-test the
wrapper.

`readlink` writes into a caller-supplied buffer WITHOUT
NUL-terminating it. Callers that want a C-string must
compare the return value against the buffer size (values
equal to `bufsize` mean the target was truncated) and write
their own terminator.

`truncate` and `ftruncate` are the same operation with
different argument shapes — one takes a path, one takes an
open fd. Both extend a shorter file with zeros and shrink a
longer one, without adjusting the file position of any
process that has the file open.

`stat` is the path-based counterpart to `fstat` — it writes
the same 144-byte struct, with the same offsets, but resolves
its target by name instead of by open fd. Follows symbolic
links along `path`. A caller-side symmetry with `io_size`
(currently fd-based) is a natural follow-up if a `path`-based
size helper is ever needed.

`rename` atomically moves a directory entry. Both platforms
reject cross-filesystem moves with `-EXDEV`. Directory
semantics: macOS returns `-ENOTEMPTY` when the destination is
a non-empty directory; Linux allows replacing an empty
destination directory, `-ENOTEMPTY` otherwise.

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
extern fstat, unlink, mkdir, rmdir              ; v1.1
extern stat, rename                             ; v1.2
extern lstat, chmod, chown, symlink, readlink   ; v1.3
extern truncate, ftruncate                      ; v1.3
extern getdents                                 ; v1.4
extern unlinkat, mkdirat, renameat, fstatat     ; v1.5
extern symlinkat, linkat, readlinkat            ; v1.5
extern fchmodat, fchownat                       ; v1.6
extern io_size                                  ; v1.1 util helper
extern dir_iter_open, dir_iter_next             ; v1.4 util
extern dir_iter_close                           ; v1.4 util
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
  `1..C` cover v1.0's five wrappers on a real mktemp'd file.
  `D..I` cover v1.1's metadata + namespace ops. `J..O` cover
  v1.2's `stat` + `rename`. `P..c` chain a fresh tempfile
  through v1.3: `ftruncate` shrinks it, `io_size` verifies,
  path-based `truncate` shrinks it again and `stat` verifies,
  `chmod` + `chown(-1,-1)` succeed, `symlink` creates a link
  and `readlink` reads it back, `lstat` inspects the link
  itself, then both are unlinked. `d..f` cover v1.4: iterate
  a pre-populated ITER_DIR (`mktemp -d` + three regular
  files), verify exactly 5 entries (`.`, `..`, `a`, `b`, `c`),
  then close the iterator. `g..s` cover v1.5: open a fresh
  AT_DIR to get a dirfd, then chain every `*at()` symbol
  through it — mkdirat/unlinkat(AT_REMOVEDIR) round-trip,
  openat + renameat, fstatat + symlinkat + readlinkat,
  linkat, and unlinkat cleanup of each entry, ending in a
  close of the dirfd. `t..y` cover v1.6: reopen AT_DIR, create
  a scratch file "f", `fchmodat` and `fchownat(-1,-1)` succeed,
  unlinkat the file, close the dirfd.
- [`fail-smoke.asm`](test/fail-smoke.asm) — failure path. Each
  wrapper is called with args the kernel is guaranteed to
  reject (`/proc/libio/does-not-exist-` → `-ENOENT` for
  `open`, `openat`, `unlink`, `mkdir`, `rmdir`, `stat`,
  `rename`, `lstat`, `chmod`, `chown`, `symlink`, `readlink`,
  `truncate`; `fd=999999` → `-EBADF` for `lseek`, `pread`,
  `pwrite`, `fstat`, `ftruncate`, `getdents`, each of the
  seven v1.5 `*at()` wrappers, and each of the two v1.6
  `*at()` wrappers when their dirfd is bad).
  Exercises the macOS `SYSCALL_NORM` `neg rax` line on
  every export.
- [`c-smoke.c`](test/c-smoke.c) — verifies `libio.a` is linkable
  and callable from a normal C toolchain. Uses GCC `__asm__`
  labels to bind libio calls to their bare names (bypassing
  Mach-O's underscore convention). Exercises every exported
  symbol end-to-end so a C consumer's link line is proven
  to work.

On success the runner prints one line per test:

```text
PASS: io-smoke     output=[PASS]
PASS: fail-smoke   output=[PASS]
PASS: c-smoke      output=[PASS]
```

Both platforms are exercised on CI.

## What is not here — yet

v1.6 covers the `*at()` permission / owner variants (`fchmodat`,
`fchownat`) on top of v1.5's `*at()` core. Still deferred:

- `utimensat` — see the v1.6 symbol section for the reason.
  Would require a per-platform helper on macOS (dispatching
  to `setattrlistat` with an `attrlist` struct); on Linux it
  is just `SYS_utimensat`. Add if a real consumer needs it.
- `access`, `faccessat` — permission checks. Skipped for now
  since `open` + errno is more informative.
- `dup`, `dup2`, `pipe` — fd-graph manipulation. Useful for
  process plumbing but out of scope for the file-oriented
  archive.
- `flock`, `fcntl` — advisory locking / fd flag mutation.
  Both have large flag surfaces; deferred until a real
  consumer justifies picking a subset.
- Async I/O and event notification (`kqueue`, `epoll`,
  `io_uring`). Each is a full archive on its own.

## Utility helpers

`util/` (added in v1.1) holds pure-computation helpers that
sit on top of one or more syscall wrappers. Currently:

- [`io_size`](util/io-size.asm) — calls `fstat` and extracts
  `st_size` at the platform-specific offset, storing the
  result in a caller-supplied `long*`. Removes the need for
  callers to know that `ST_SIZE_OFF` is `96` on macOS and
  `48` on Linux.
- [`dir_iter_*`](util/dir-iter.asm) — a portable directory
  iterator built on `getdents`. Hides the per-platform
  `d_type` (macOS `+20`, Linux `+18`) and `d_name` (macOS
  `+21`, Linux `+19`) offsets behind an
  `open`/`next`/`close` triple whose state lives in a
  caller-allocated opaque block.

Future helpers that compose a common file-I/O pattern into
one call belong here rather than in `syscall/`.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`).
- [`../sock/`](../sock/) — Berkeley sockets syscall wrappers
  plus the `<arpa/inet.h>` byte-order and text helpers.
  Consumers of `libio.a` typically also link `libsock.a` for
  `read`, `write`, and `close`.
