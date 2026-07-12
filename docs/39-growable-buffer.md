# Growable byte buffer

Every static buffer in this repo so far assumes a
compile-time size. That works when the input length is known
in advance — a fixed message, a page-sized read, a
known-length line. It breaks the moment the caller cannot say
in advance how large the payload will be. libbuf plugs that
gap with a small mmap-backed vector:

```
buf_init   (bufp, initial_cap)           → 0 or -errno
buf_reserve(bufp, needed)                → 0 or -errno
buf_append (bufp, src, n)                → 0 or -errno
buf_reset  (bufp)                        → (void)
buf_free   (bufp)                        → 0 or -errno
```

## The `struct buf` layout

`bufp` points at a 24-byte struct the caller allocates —
typically `resb BUF_SIZE` in `.bss`. libbuf never allocates
the struct itself; it owns only the mmap region referenced
from it.

```
+0    data   u64   pointer to mmap'd bytes (0 before init /
                   after free)
+8    len    u64   used-byte count, 0 <= len <= cap
+16   cap    u64   mmap'd capacity, multiple of BUF_PAGE_SIZE
```

Placing the struct in `.bss` guarantees a zero-initialized
starting state, so `buf_free` on a never-`init`'d buffer is a
clean no-op — the `data == 0` check short-circuits before
touching the kernel.

## Grow strategy

`buf_reserve(bufp, needed)` is a no-op when `cap >= needed`.
Otherwise it computes

```
new_cap = max(cap * 2, needed) rounded up to BUF_PAGE_SIZE
```

Doubling gives amortized O(1) per byte appended. The
page-granularity round-up matches the mmap unit without
needing a syscall to query the runtime page size.
`buf_append` calls `buf_reserve(len + n)` before every copy,
so the grow is transparent to the caller.

## Pointer stability

**A grow relocates the mapping.** The whole grow path is
`mmap` a new region, `memcpy` the first `len` bytes into it,
then `munmap` the old region. Any raw pointer the caller was
holding into `data` before the grow is now dangling. The
right shape is: read `[bufp + BUF_DATA_OFF]` *fresh* after any
call that might grow (`buf_reserve`, `buf_append`).

This is deliberate. The alternative — reserving a large
virtual address hole up front and `mprotect`ing pages on
demand — keeps pointers stable at the cost of a more complex
init. libbuf ships the honest simple form; the stable-pointer
variant will land alongside the first parser that actually
needs it.

## Why no `mremap`

Linux has `mremap(2)`, which can resize a mapping in place
and often avoids the memcpy. macOS has no equivalent. The
portable answer — `mmap-new` + `memcpy` + `munmap-old` — is
one syscall pair plus a byte copy on both platforms, so
libbuf uses that unconditionally. A future asymmetric variant
could branch on Linux to use `mremap`; the current version
prefers a single code path.

## See also

- [`libs/buf/`](../libs/buf/) — the archive: five entry
  points, one `.inc` header for the struct offsets and mmap
  flags, no raw syscalls of its own.
- [`26-memory-mapping.md`](26-memory-mapping.md) — the
  `mmap` / `munmap` primer libbuf builds on top of.
- [`27-libraries.md`](27-libraries.md) — the archive index
  this chapter is a companion to.
- [`examples/50-growable-buf`](../examples/50-growable-buf/) —
  the runnable that slurps stdin into a libbuf and writes
  the whole accumulation back in one syscall.

## Next

- Back to [docs/README.md](README.md).
