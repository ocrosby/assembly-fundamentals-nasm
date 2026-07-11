# 30 — shared-mapping

Allocate an anonymous private page with `mmap`, write a byte
into it, read the byte back to verify the mapping is real,
release the page with `munmap`, and exit with the byte value
as the process status. Builds on
[28-fork-child](../28-fork-child/) by introducing the first
call into libio's memory-mapping primitives.

## Introduces

- **`mmap(2)` and `munmap(2)`.** The syscalls that turn a
  request for `N` bytes of virtual memory (backed by
  anonymous zero-fill, a file, or a shared segment) into a
  pointer the process can dereference — and, at the end of
  its useful life, release that pointer back to the kernel.
  libio's [v1.9 mmap wrapper](../../libs/io/syscall/mmap.asm)
  handles the six-argument SysV → syscall register shuffle
  (SYSCALL_ARG4 puts `flags` in `r10`; `fd` and `offset`
  already match the kernel's `r8`/`r9` slots).
- **The `MAP_ANON` platform split.** macOS spells the
  anonymous flag `0x1000`, Linux spells it `0x20`. Both come
  from the same `<sys/mman.h>` header on their respective
  systems. `libs/io/syscall/syscall.inc` collapses this
  behind a single `MAP_ANON` name; this example spells it
  out inline via `%ifdef MACOS` to keep the source
  self-contained without pulling in the shared include.
- **`fd = -1` for anonymous mappings.** The convention that
  says "there is no backing file; give me zero-filled
  pages". The kernel enforces `offset = 0` in this mode.

## Why the exit code is 42

`_exit(42)` gives the CI harness a distinctive value to
verify — an exit of 0 would look identical to a program that
crashed early and got reaped with a default status.
Threading the byte we wrote through the exit register
(`mov edi, r12d`) forces the whole write-then-read cycle to
actually complete: if the mapping had been read-only, the
write would have crashed with SIGSEGV; if the read had come
from unmapped memory, likewise. A clean `exit=42` at the
end proves both worked.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
