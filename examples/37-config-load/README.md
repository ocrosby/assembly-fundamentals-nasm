# 37 — config-load

Parse a `KEY=VALUE` line out of a config file using libio's
`file_read_all` to load the file and libstr's `strchr` +
`memcmp` to walk the buffer. Exits 42 on success.

First example to use two archives on the same buffer: libio
hands the caller a `PROT_READ` view of the whole file, and
libstr walks it byte-by-byte.

## Introduces

- **`file_read_all` (libio v1.12).** Hands the caller an
  addr + size for a mmap'd view of the file. The caller
  owns the mapping and calls `munmap` when done — this
  example demonstrates the ownership contract end-to-end.
- **Two archives, one buffer.** libio owns the bytes;
  libstr walks them. Callers link both archives; the two
  don't know about each other and don't need to.
- **`memcmp` + `strchr` composition.** The classic
  "does this start with X? then find the separator" pattern
  that shows up in every configuration parser.

## Config format

One line, LF-terminated:

```
ANSWER=42
```

The example seeds the file (`/tmp/nasm-config.txt`) with a
raw `sys_write` before parsing, so the whole flow runs in
one process. A real caller would skip that step.

## Program flow

```
Seed /tmp/nasm-config.txt with "ANSWER=42\n"
file_read_all(path, &addr, &size)  → PROT_READ view
memcmp(addr, "ANSWER", 6)          → 0 (key matches)
strchr(addr, '=')                  → pointer to '='
Reject anything with '=' not at addr+6 (no spaces)
Decode two digits after '=' as decimal
munmap(addr, size)                 → caller-owned cleanup
exit(value)                        → 42
```

The two-digit decode keeps the example small — a real
config parser would run an atoi loop, but atoi is not the
concept this example is here to teach.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
