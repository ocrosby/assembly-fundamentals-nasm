# 31 — mmap-file

Create a page-sized scratch file, drop the byte value 42 at
offset 0, then read that byte back through a file-backed
mmap. Exits with the byte value (42) on success. Builds on
[30-shared-mapping](../30-shared-mapping/) by swapping the
anonymous mapping for a real file behind the address range.

## Introduces

- **File-backed `mmap`.** Drop `MAP_ANON`, pass a real fd
  and offset. The kernel now backs the mapping with the
  file's contents; reads through the mapping return the
  file's bytes, and writes (were we using `PROT_WRITE`)
  would eventually reach disk on `msync` or unmap.
- **`ftruncate(2)`.** The syscall that grows or shrinks a
  file to a specific size, zero-filling any new bytes.
  Used here to size the scratch file to `PAGE_SIZE` before
  the mmap — a shorter file would let the mapping's tail
  read past EOF, which raises `SIGBUS` on Linux (macOS
  zero-fills instead, but depending on that would be
  platform-brittle).
- **`pwrite(2)` at a fixed offset.** Positioned write —
  does not touch the fd's seek offset, so it composes with
  later reads or seeks without the caller having to save
  and restore state. Used to overwrite the file's first
  byte with 42 in a single call.

## Program flow

```
open(path, O_RDWR|O_CREAT|O_TRUNC, 0600)   → fd
ftruncate(fd, 4096)                        → 4KB of zeros
pwrite(fd, byte42, 1, 0)                   → byte at offset 0 = 42
mmap(NULL, 4096, PROT_READ, MAP_PRIVATE, fd, 0) → addr
byte_read = *(uint8_t*)addr                → 42
munmap(addr, 4096)
exit(byte_read)                            → 42
```

The exit-code trick — return the byte we read back —
doubles as an end-to-end assertion: any wrong byte or
segfault produces a different exit and fails CI.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
