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

**v1.7 — fd-graph manipulation:**

| Symbol | Arguments             | Returns                              |
| ------ | --------------------- | ------------------------------------ |
| `dup`  | `oldfd`               | new fd or negative errno             |
| `dup2` | `oldfd`, `newfd`      | `newfd` or negative errno            |
| `pipe` | `pipefd*` (int[2])    | `0` or negative errno; writes both fds into the array |

**v1.8 — fd flags + advisory locks:**

| Symbol  | Arguments             | Returns                                        |
| ------- | --------------------- | ---------------------------------------------- |
| `fcntl` | `fd`, `cmd`, `arg`    | command-specific value or negative errno       |
| `flock` | `fd`, `operation`     | `0` or negative errno                          |

**v1.9 — memory mapping:**

| Symbol   | Arguments                                             | Returns                                        |
| -------- | ----------------------------------------------------- | ---------------------------------------------- |
| `mmap`   | `addr*`, `len`, `prot`, `flags`, `fd`, `offset`       | mapped address (positive) or negative errno    |
| `munmap` | `addr*`, `len`                                        | `0` or negative errno                          |

`mmap` takes six arguments — SYSCALL_ARG4 shifts the 4th
(`flags`) from SysV `rcx` to syscall `r10`; `r8` and `r9`
already match the kernel-side slots. `syscall.inc` exports
`PROT_NONE` / `PROT_READ` / `PROT_WRITE` / `PROT_EXEC` (values
agree across platforms) and the sharing/behavior flags
`MAP_SHARED` / `MAP_PRIVATE` / `MAP_FIXED` (values also agree)
plus the per-platform `MAP_ANON` (Darwin `0x1000`, Linux
`0x20`, resolved by the header). Callers pass `MAP_ANON`
uniformly and the right numeric value is baked in at
assembly time.

Common patterns:

- Anonymous scratch page:
  `mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_ANON|MAP_PRIVATE, -1, 0)`
- File-backed read-only view:
  `mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, 0)`
- Shared writable view (IPC between processes on the same
  file): `mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0)`

`munmap` is a two-argument pass-through. The address and
length passed in must match a prior `mmap` — the kernel
tolerates a wider range (unmapping whatever intersects),
but relying on that is a common way to accidentally free
someone else's memory.

**v1.10 — scatter/gather I/O:**

| Symbol   | Arguments                             | Returns                              |
| -------- | ------------------------------------- | ------------------------------------ |
| `readv`  | `fd`, `iov*`, `iovcnt`                | bytes read (0 = EOF) or negative errno |
| `writev` | `fd`, `iov*`, `iovcnt`                | bytes written or negative errno      |

`readv` and `writev` are the "one syscall, many buffers"
primitives. `writev` gathers `iovcnt` buffers into a single
output stream on `fd`; `readv` scatters an input stream into
`iovcnt` buffers, filling each in order until the total
requested length is delivered or an EOF / error arrives.

The `iov*` argument points at an array of `struct iovec`,
which is 16 bytes on both platforms:

- `+0`: `iov_base` (8 bytes) — pointer to the buffer
- `+8`: `iov_len`  (8 bytes) — number of bytes at that
  pointer

`syscall.inc` exports `IOV_BASE_OFF = 0`, `IOV_LEN_OFF = 8`,
and `IOVEC_SIZE = 16`. Callers usually build iovec arrays on
the stack or in `.bss` — no allocation cost. `iovcnt` is
bounded by the kernel's `IOV_MAX` (16 on Darwin, 1024 on
Linux); over-sized calls return `-EINVAL`.

The interesting property: the sender and receiver do not
have to agree on where iovec boundaries sit. A `writev` of
three 4-byte chunks and a `readv` of two 6-byte chunks
against the same pipe read/write pair produces the same
12 bytes in the receiver's split, because the kernel treats
both sides as a byte stream — the iovec is just the
process-side scatter/gather description, not a wire format.

`fcntl` is a pass-through wrapper — its return value depends on
the command:

- `F_GETFD`, `F_GETFL` — return the flags value
- `F_SETFD`, `F_SETFL` — return `0` on success
- `F_DUPFD` — return a new fd

The most common patterns callers reach for are round-tripping
`F_GETFL` → `F_SETFL` with the `O_NONBLOCK` bit toggled (making
a socket or pipe non-blocking) and setting `FD_CLOEXEC` via
`F_SETFD` so the fd doesn't survive `execve`. `syscall.inc`
exports both the `F_*` command codes and the `O_NONBLOCK` /
`O_APPEND` bits (whose numeric values differ per platform).

`flock` is BSD advisory locking. Values agree across macOS and
Linux, `LOCK_SH` / `LOCK_EX` / `LOCK_UN` for shared / exclusive
/ unlock, `LOCK_NB` OR'd in to make the call non-blocking
(return `-EWOULDBLOCK` instead of waiting). The lock is
associated with the open file description, so `dup` and `fork`
share it, but two independent `open` calls to the same file get
independent locks. Not portable across NFS — use `fcntl` POSIX
locking (`F_SETLK`, deferred here) if the file may live on a
network filesystem.

`dup` and `dup2` are one-liner syscall wrappers — Darwin and
Linux agree on the calling convention. `pipe` is the outlier:
its Linux syscall writes both fds into the caller-supplied
`int[2]` and returns `0`/`-errno` conventionally, but the
macOS BSD syscall (42) returns the read end in `rax` and the
write end in `rdx` directly. libio's wrapper hides that
difference — callers pass an `int[2]` on both platforms; on
macOS the wrapper saves the pointer, runs the syscall, and
if it succeeds fans `rax` and `rdx` into `pipefd[0]` and
`pipefd[1]` before returning `0`. Fully documented in
[`pipe.asm`](syscall/pipe.asm).

`dup`'s returned fd never has `FD_CLOEXEC` set even if the
source did (POSIX rule). `dup2` closes the destination fd
atomically before pointing it at the new open file
description — critical for `stdin` / `stdout` redirection in
child processes without a race window where the destination
is closed but nothing has taken its place.

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
extern dup, dup2, pipe                          ; v1.7
extern fcntl, flock                             ; v1.8
extern mmap, munmap                             ; v1.9
extern readv, writev                            ; v1.10
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

`make test` builds `libio.a` and runs five smoke tests via the
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
- [`fdgraph-smoke.asm`](test/fdgraph-smoke.asm) — v1.7's
  `dup`, `dup2`, and `pipe`. Nine sub-checks: pipe → two
  positive fds → write + read a two-byte payload across the
  pipe (via raw `read`/`write` syscalls to avoid pulling
  libsock in for two bytes) → dup the read end → dup2 into
  fd 50 → clean up every fd → sub-check 9 confirms
  `dup(BAD_FD)` returns negative. Lives in a separate file
  because `io-smoke` has exhausted its single-character
  sub-check ID space (`1..9`, `A..Z`, `a..y`).
- [`fcntl-smoke.asm`](test/fcntl-smoke.asm) — v1.8's `fcntl`
  and `flock`. Twelve sub-checks: pipe fixture → `F_GETFL`
  reads the current flags → `F_SETFL` sets `O_NONBLOCK` →
  `F_GETFL` confirms the bit → a raw read on the empty pipe
  returns `-EAGAIN` (proves the flag reached the kernel) →
  `F_SETFD` sets `FD_CLOEXEC` → `F_GETFD` confirms → open a
  scratch tempfile → `flock(LOCK_EX|LOCK_NB)` and
  `flock(LOCK_UN)` succeed → close and unlink.
- [`mmap-smoke.asm`](test/mmap-smoke.asm) — v1.9's `mmap`
  and `munmap`. Four sub-checks: anonymous `MAP_PRIVATE` RW
  page allocation → byte-level round trip through the
  mapping → `munmap` releases it → non-anonymous mmap with
  a bogus fd forces `SYSCALL_NORM`'s failure branch
  (returns negative errno). macOS's raw kernel accepts
  `length = 0` even though libc rejects it, so the error
  probe uses a bad fd rather than a zero length.
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
PASS: fdgraph-smoke output=[PASS]
PASS: fcntl-smoke  output=[PASS]
PASS: mmap-smoke   output=[PASS]
PASS: c-smoke      output=[PASS]
```

Both platforms are exercised on CI.

## What is not here — yet

v1.8 covers fd-flag mutation (`fcntl` for `F_SETFL O_NONBLOCK`,
`F_SETFD FD_CLOEXEC`, etc.) and BSD advisory locking (`flock`)
on top of v1.7's fd-graph surface. Still deferred:

- `utimensat` — see the v1.6 symbol section for the reason.
  Would require a per-platform helper on macOS (dispatching
  to `setattrlistat` with an `attrlist` struct); on Linux it
  is just `SYS_utimensat`. Add if a real consumer needs it.
- `access`, `faccessat` — permission checks. Skipped for now
  since `open` + errno is more informative.
- `fcntl` POSIX locking (`F_SETLK`, `F_SETLKW`, `F_GETLK`).
  These need a `struct flock` argument whose layout differs
  between macOS and Linux; would want an `io_lock_*` helper
  in `util/` that hides the marshalling. `flock` covers the
  simpler advisory-lock case for now.
- Async I/O and event notification (`kqueue`, `epoll`,
  `io_uring`). Each is a full archive on its own.
- `pipe2` (Linux) — the flag-taking variant. libsock's
  `poll` / `select` cover the "why would you want that" case
  for most consumers; add if a real target needs
  `O_CLOEXEC` set atomically at pipe-creation time.

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
- [`file_write_all`](util/file-write-all.asm) *(v1.13)* —
  `file_write_all(path, addr, size)` dumps a caller-owned
  buffer into a fresh file at `path`, creating or truncating
  the destination as needed. Handles short writes internally
  by looping in userspace (matching libsock's `send_all`
  pattern). Symmetric counterpart to `file_read_all`: one
  gives you a file as a buffer, the other writes a buffer as
  a file. `size = 0` is legal and still creates/truncates
  the destination.
- [`file_read_all`](util/file-read-all.asm) *(v1.12)* —
  `file_read_all(path, out_addr, out_size)` returns a
  PROT_READ MAP_PRIVATE view of the whole file as one
  contiguous buffer, plus its size. Opens the file, reads
  the size via `io_size`, mmaps the file, closes the fd
  (the mapping outlives the fd on both platforms), and
  writes `*out_addr` and `*out_size`. Ownership contract:
  the caller is responsible for `munmap(addr, size)` when
  done. Zero-length files return `addr = NULL`, `size = 0`
  so callers get a clear sentinel rather than a
  platform-specific `mmap(len=0)` wart.
- [`file_copy`](util/file-copy.asm) *(v1.11)* —
  `file_copy(src_path, dst_path)` folds the two-mmap file
  copy pattern (see
  [`examples/35-mmap-copy/`](../../examples/35-mmap-copy/))
  into one call. Opens both files, sizes the source via
  `io_size`, `ftruncate`s the destination, mmaps both
  (source `PROT_READ MAP_PRIVATE`, destination
  `PROT_READ|PROT_WRITE MAP_SHARED`), `rep movsb`s the
  bytes across, unmaps and closes. Returns `0` on success,
  negative errno on failure. Zero-length sources
  short-circuit past the mmap dance (Linux `mmap(len=0)`
  is `-EINVAL`). No libstr or libsock coupling — `close`
  is inlined via raw syscall the same way
  `dir_iter_close` does.

Future helpers that compose a common file-I/O pattern into
one call belong here rather than in `syscall/`.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`).
- [`../sock/`](../sock/) — Berkeley sockets syscall wrappers
  plus the `<arpa/inet.h>` byte-order and text helpers.
  Consumers of `libio.a` typically also link `libsock.a` for
  `read`, `write`, and `close`.
