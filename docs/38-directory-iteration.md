# Directory iteration

Reading a directory is not "open, read, print" — a directory
is not a stream of text but a stream of variable-length
records the kernel produces one syscall at a time. libio
hides that shape behind a small iterator so callers walk
directories the same way on macOS and Linux:

```
dir_iter_open (iter, path)                                → 0 or -errno
dir_iter_next (iter, name_buf, name_bufsize, type_out)    → 1 (entry),
                                                            0 (end),
                                                            -errno
dir_iter_close(iter)                                      → 0 or -errno
```

## The iterator has no hidden state

`iter` is a caller-supplied buffer of `DIR_ITER_SIZE` bytes
(4128) — one 4 KiB kernel refill area plus a few bookkeeping
slots. Reserve it in `.bss` with `resb DIR_ITER_SIZE` and
libio needs no allocator, no globals, no thread-local
storage. The fd, the cursor into the refill buffer, and the
resume position all live in the same block.

That makes the iterator trivially thread-safe (one buffer
per thread) and trivially cheap to allocate. It is also the
reason `dir_iter_close` on a failed `dir_iter_open` is a
no-op: the negative fd from a failed `open` stays in the
same slot and the close wrapper checks the sign before
issuing the syscall.

## The per-entry contract

Every successful `dir_iter_next` call fills three outputs:

- **`name_buf`** — NUL-terminated entry name. If the entry
  is too long to fit, the call returns `-ENAMETOOLONG`
  (`-63` on macOS, `-36` on Linux) *and still advances the
  iterator*, so the next call moves on to the next entry.
- **`*type_out`** — one of the `DT_*` constants below.
- **`rax`** — `1` for "have entry", `0` for "end of
  directory", or a negative errno.

Entries include `.` and `..`. The iterator matches
`readdir(3)`; callers that want to skip the dot entries do
a two-character check on `name_buf` and continue.

## `DT_*` type constants

The numeric values below are identical on both platforms
(BSD's ancient assignment), so `syscall.inc` defines them
once:

| Constant     | Value | Meaning                       |
| ------------ | ----: | ----------------------------- |
| `DT_UNKNOWN` |     0 | Type not filled by the FS.    |
| `DT_FIFO`    |     1 | Named pipe.                   |
| `DT_CHR`     |     2 | Character device.             |
| `DT_DIR`     |     4 | Directory.                    |
| `DT_BLK`     |     6 | Block device.                 |
| `DT_REG`     |     8 | Regular file.                 |
| `DT_LNK`     |    10 | Symbolic link.                |
| `DT_SOCK`    |    12 | Unix socket.                  |

`DT_UNKNOWN` is a legal answer on filesystems that do not
store the type in the directory entry (some older ext
variants). Portable callers that need to know fall back to
`stat` on `name_buf`.

## Underneath: two different syscalls

The wire format the kernel returns is not portable, so
`dir_iter_next` reads through libio's `getdents` wrapper:

- **Linux** uses `getdents64`. The fd's own file position
  carries the resume state; the `position*` argument
  libio's wrapper takes is ignored.
- **macOS** uses `getdirentries64`. The kernel expects an
  in-out `position` cookie the caller threads through
  every call, letting the same fd be resumed from an
  earlier offset.

The two record layouts also differ — `d_reclen` sits at
offset 16 on macOS, and `d_type` / `d_name` follow at 20
and 21; on Linux the equivalent offsets are 16, 18, 19.
`syscall.inc` names both sets under
`D_RECLEN_OFF`, `D_TYPE_OFF`, and `D_NAME_OFF`, and the
iterator picks the platform's constants at assemble time.

## Why not `readdir(3)`?

libc's `readdir` allocates, retains internal buffers, and
is (historically) not thread-safe. The reentrant variant
`readdir_r` was deprecated even in glibc. Doing the same
work with a fixed-size caller-supplied buffer means no
allocator dependency, no thread-safety footnote, and no
`errno` global to consult — the same shape every other
libio call uses.

## See also

- [`libs/io/util/dir-iter.asm`](../libs/io/util/dir-iter.asm)
  — the iterator implementation.
- [`libs/io/syscall/getdents.asm`](../libs/io/syscall/getdents.asm)
  — the platform-splitting syscall wrapper.
- [`30-io.md`](30-io.md) — the file family this iterator
  sits alongside.
- [`27-libraries.md`](27-libraries.md) — the archive index
  this chapter is a companion to.
- [`examples/45-dir-iter`](../examples/45-dir-iter/) — the
  runnable that seeds a scratch directory and counts
  `DT_REG` entries.

## Next

- Back to [docs/README.md](README.md).
