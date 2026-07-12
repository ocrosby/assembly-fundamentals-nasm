# 35 — mmap-copy

Copy a small file into a fresh destination file using two
mmap regions instead of a read/write loop. Exits 42 on
success. Builds on [31-mmap-file](../31-mmap-file/) and
[32-mmap-shared](../32-mmap-shared/) by holding two mappings
live at once and moving bytes between them entirely in
userspace.

## Introduces

- **Two mmap regions live at once.** Prior examples used one
  mapping; this example holds a `PROT_READ MAP_PRIVATE` view
  of the source and a `PROT_READ|PROT_WRITE MAP_SHARED` view
  of the destination simultaneously. The copy is a plain
  `mov`-based byte loop through both mappings.
- **Memory-mapped I/O for the copy path.** No `read` or
  `write` syscall runs during the byte transfer — the kernel
  only sees the two `mmap` calls at setup, the destination's
  writes reaching the underlying file on flush/unmap, and the
  final `munmap` pair. This is the stripped-down form of the
  "memory-mapped I/O beats read/write for small regions"
  pattern.
- **`MAP_SHARED` on a fresh destination file.** Prior
  `MAP_SHARED` was against an *anonymous* page across `fork`
  ([32-mmap-shared](../32-mmap-shared/)); here it is against
  a *file*. `MAP_PRIVATE` on the destination would keep the
  writes in this process's page cache and the file on disk
  would stay all zeros — a misconfiguration this example
  catches by verifying `dst[0] == 'H'` after the copy.

## Program flow

```
open(src, O_RDWR|O_CREAT|O_TRUNC, 0600) → src_fd
ftruncate(src_fd, 12)                   → 12 zero bytes
pwrite(src_fd, "HELLO WORLD!", 12, 0)   → source seeded

src = mmap(NULL, 12, PROT_READ, MAP_PRIVATE, src_fd, 0)

open(dst, O_RDWR|O_CREAT|O_TRUNC, 0600) → dst_fd
ftruncate(dst_fd, 12)                   → 12 zero bytes
dst = mmap(NULL, 12, PROT_READ|PROT_WRITE,
           MAP_SHARED, dst_fd, 0)

for i in 0..11:  dst[i] = src[i]        ; inline byte copy

assert dst[0] == 'H'                    ; end-to-end check
munmap(src, 12); munmap(dst, 12)
exit(42)
```

The exit code is 42 rather than the copied byte because 'H'
(0x48) is a less recognizable sentinel than the 42 the other
mmap examples in this repo use. The `dst[0] == 'H'` check
before exiting keeps the assertion that the copy actually
landed the right byte, without breaking the family
convention.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
