# libs/buf/

Mmap-backed growable byte buffer packaged as the static archive
`libbuf.a`. Callers reserve a fixed-size `struct buf` (24 bytes,
`BUF_SIZE` in `buf.inc`) and libbuf owns the data region behind
it — mmap on init, doubling grows through mmap-copy-munmap on
reserve, munmap on free.

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Version

**v1.0** — first release. Five entry points cover the common
lifecycle: init, reserve, append, reset, free. Composes
`libio`'s `mmap` and `munmap`; owns no raw syscalls.

## Exported symbols

Consumer object files link with `libbuf.a` and `libio.a`. No
libc dep; no libSystem dep on macOS.

| Symbol         | Args                          | Return       | Notes                                                                 |
| -------------- | ----------------------------- | ------------ | --------------------------------------------------------------------- |
| `buf_init`     | `bufp`, `initial_cap`         | 0 or -errno  | rounds `initial_cap` up to `BUF_PAGE_SIZE`. Zero → one page.          |
| `buf_free`     | `bufp`                        | 0 or -errno  | no-op success if data is already NULL. Zeros the struct either way.   |
| `buf_reserve`  | `bufp`, `needed`              | 0 or -errno  | no-op if `cap >= needed`. Else grows to `max(cap*2, needed)`, page-aligned. Relocates the data pointer on grow. |
| `buf_append`   | `bufp`, `src`, `n`            | 0 or -errno  | reserves `len+n`, memcpy, advances `len`.                             |
| `buf_reset`    | `bufp`                        | (void)       | `len = 0`; data/cap unchanged. Cheap "start a fresh message" call.    |

All routines follow the archive's calling convention: SysV
AMD64 arguments in `rdi`, `rsi`, `rdx`; negative errno in `rax`
on failure; callee-saved registers preserved.

## The `struct buf` layout

Defined in `buf.inc`:

```
+0    data   u64   pointer to mmap'd bytes (0 before init /
                   after free)
+8    len    u64   used-byte count, 0 <= len <= cap
+16   cap    u64   mmap'd capacity in bytes, multiple of
                   BUF_PAGE_SIZE
```

Reserve the struct in `.bss` with `resb BUF_SIZE`. libbuf never
allocates the struct itself.

## Pointer stability

**A successful `buf_reserve` or `buf_append` may relocate the
mapping.** Any pointer a caller was holding into the old
`data` region is invalidated. Recompute pointers by reading
`[bufp + BUF_DATA_OFF]` after every call that might grow.

This is the honest, portable form: macOS has no `mremap`, so
grow is always `mmap-new + memcpy + munmap-old`. A future
version could reserve a large virtual address hole up-front
and mprotect pages on demand to keep the pointer stable, at
the cost of a more complex init.

## Grow strategy

`buf_reserve` doubles the current capacity, taking the max
against the requested `needed`, then rounds up to
`BUF_PAGE_SIZE` (4096). Doubling gives amortized O(1) per byte
appended; the page-granularity rounding matches the mmap unit
without needing a syscall to query the runtime page size.

## Dependency graph

```
libbuf → libio (mmap, munmap)
```

Nothing else. Build order enforced by the top-level `Makefile
test` target — `libio` builds first.

## Building

```
make          # produces libbuf.a
make build    # object files only
make test     # rebuild + run the smoke
make clean
```

## Not here yet

- **Stable-pointer variant.** A `buf_init_hole(bufp, max_cap)`
  that reserves `max_cap` bytes of address space up-front with
  `PROT_NONE` and grows by `mprotect`. Useful for parsers that
  want to hold pointers into the buffer across appends. Held
  back until a concrete caller demands it.
- **Slice / view types.** A `struct buf_view` that references a
  span into a `buf` by offset+length. Once the parser exists
  and needs to expose `Content-Type` values without copying,
  add this.
- **Bounded-capacity variant.** A `buf_append_max` that fails
  when the cap would exceed a caller-provided ceiling. Useful
  for guarding against oversized request bodies; not needed
  until the HTTP server exists.
