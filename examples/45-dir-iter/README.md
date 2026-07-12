# 45 — dir-iter

Walk a directory with libio's `dir_iter_*` helpers. Creates a
scratch directory in `/tmp`, drops three regular files into
it, then iterates the directory counting `DT_REG` entries.
Exits with `count * 14 = 42` on success.

First runnable that exercises the whole `dir_iter_*` API.

## Introduces

- **`dir_iter_open` / `_next` / `_close` (libio v1.4).** A
  caller-allocated directory iterator. The 4 KB state
  buffer lives in the caller's `.bss` — no heap dependency,
  no fd tracking outside the block, no hidden globals.
- **`DT_REG` and the portable dirent shape.** The iterator
  hides the per-platform dirent record layout (macOS puts
  `d_type` at +20, Linux at +18) and exposes only the
  DT_* constants that both platforms share. Callers filter
  by type without knowing which offset the filesystem used.

## Program flow

```
best-effort cleanup of prior-run leftovers
mkdir(scratch_path, 0700)
for name in ["a", "b", "c"]:
    open(scratch_path/name, O_WRONLY|O_CREAT, 0600); close
dir_iter_open(iter, scratch_path)
count = 0
while dir_iter_next(iter, name_buf, sizeof, &type):
    if type == DT_REG: count += 1
dir_iter_close(iter)
cleanup: unlink each file; rmdir the scratch path
exit(count * 14)                              → 42
```

The iterator yields `.` and `..` too, matching `readdir(3)`.
The `DT_REG` filter is what makes the count come out to 3
(the three files we created) rather than 5 (files plus
`.` and `..`, whose types are `DT_DIR`).

## Why `count * 14`?

Keeps the sentinel exit code visible without complicating
the read logic. If a future OS quirk makes the iterator
return an unexpected number of `DT_REG` entries, the
multiplier makes the deviation obvious in the exit code:
`2 * 14 = 28` (missed one), `4 * 14 = 56` (double-counted).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
