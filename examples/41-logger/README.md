# 41 — logger

Real-shape logger built on libio's I/O family. Uses
`file_write_all` to start a fresh log, then `file_append`
to add more records — the `O_TRUNC` vs `O_APPEND` flag
difference is what turns "replace the log" into "add to
it". Reads the accumulated file back with `file_read_all`
and verifies the exact byte sequence, then exits 42.

First runnable that uses `file_write_all`, `file_append`,
and `file_read_all` in a single flow.

## Introduces

- **`file_write_all` + `file_append` composed.**
  `file_write_all` is "start fresh"; `file_append` is
  "add more". Together they are the whole shape of a log
  writer — the first record establishes the file, every
  subsequent record grows it.
- **The full libio I/O family in one program.** After 40
  examples, this is the first that uses all three of
  `file_write_all`, `file_append`, and `file_read_all` in
  a single flow. The composition is the point.

## Records this example writes

Three records, 37 bytes total:

```
INFO: startup         (14 bytes) — via file_write_all
WARN: slow            (11 bytes) — via file_append
ERROR: down           (12 bytes) — via file_append
```

Each record ends with a single `LF`.

## Program flow

```
file_write_all(log, "INFO: startup\n", 14)  → create/truncate
file_append(log,    "WARN: slow\n", 11)     → add
file_append(log,    "ERROR: down\n", 12)    → add
file_read_all(log, &addr, &size)            → PROT_READ view
assert size == 37
byte-compare addr against the expected concatenation
munmap(addr, size)
exit(42)
```

## Why file_write_all for the first record?

`file_append` uses `O_APPEND | O_CREAT` — no `O_TRUNC`. If
a previous run left content behind, `file_append` would
grow the log past 37 bytes and the size check would fail.
`file_write_all`'s `O_TRUNC` guarantees a clean slate.

A production logger would open the file once and hold the
fd across all writes, saving the per-record `open` + `close`
overhead. This example makes the composition visible
instead.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`. The scratch file
`/tmp/nasm-logger.log` holds the three records in order
after the run.

## Next

- Back to [examples/README.md](../README.md).
