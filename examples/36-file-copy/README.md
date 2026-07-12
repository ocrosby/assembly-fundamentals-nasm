# 36 — file-copy

Copy a small file into a fresh destination via libio's
`file_copy` composed helper. Exits 42 on success. Companion
to [35-mmap-copy](../35-mmap-copy/) — 35 spells the two-mmap
sequence out inline; 36 calls one helper instead.

## Introduces

- **`file_copy` (libio v1.11).** The composed helper that
  folds the open + ftruncate + double-mmap + rep-movsb +
  munmap sequence into a single call. Callers pass
  source and destination paths; libio does the rest and
  returns `0` on success or a negative errno on failure.
- **When to reach for a composed helper.** 35-mmap-copy is
  the reference implementation of the pattern — it exists
  so the reader can see every syscall in play. 36-file-copy
  is what production code looks like after the pattern has
  been captured in a library. Both are correct; they answer
  different questions ("how does it work?" vs. "how do I
  use it?").

## Program flow

```
open(src, O_WRONLY|O_CREAT|O_TRUNC, 0600) → src_fd
write(src_fd, "HELLO WORLD!", 12)         → seed source
close(src_fd)
file_copy(src_path, dst_path)             → 0 on success
exit(42)
```

The `write` and `close` on the source fd use raw `sys_write`
and `sys_close` instead of library helpers — libio does not
export `write` (that lives in libsock, per the two-archive
rule from [`libs/README.md`](../../libs/README.md)), and
pulling libsock in for one call would obscure the "look how
short it becomes" point of the example.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`. The destination file
`/tmp/nasm-file-copy.dst` should contain `HELLO WORLD!`
after the run.

## Next

- Back to [examples/README.md](../README.md).
