# 50 — growable-buf

Slurp all of standard input into an mmap-backed growable byte
buffer, then write the accumulated content back to standard
output in a single `sys_write` call. Exit 42 on success.

First runnable that uses `libbuf`, the mmap-backed growable
byte vector introduced in the same commit range. Every
earlier read/echo example (from
[08-echo-loop](../08-echo-loop/) onward) wrote each read
chunk straight back — the loop was symmetric because the
buffer had a fixed size. This example decouples the two
sides: reads stay chunked, the write is one big call over
whatever total size arrived.

## Introduces

- **`buf_init(&b, 0)` (libbuf).** Reserve a `BUF_SIZE`-byte
  struct in `.bss` with `resb BUF_SIZE`, then hand libbuf a
  pointer plus a starting capacity. Zero is legal — libbuf
  rounds up to one page (`BUF_PAGE_SIZE`, 4096 bytes), which
  covers a typical shell prompt of input without ever
  growing.
- **`buf_append(&b, src, n)` (libbuf).** Copy `n` bytes into
  the buffer at position `len`; if the current mapping can't
  hold `len + n`, libbuf grows via `mmap-new` + `memcpy` +
  `munmap-old`. Amortized O(1) per byte appended.
- **`buf_free(&b)` (libbuf).** `munmap` the region and zero
  the struct.
- **The single-write flush.** Reading `[b + BUF_DATA_OFF]`
  *after* the read loop reflects any grows that happened
  during accumulation. Any pointer taken before the loop
  would be stale.

## Program flow

```
buf_init(&b, 0)
loop:
    n = read(0, chunk, 128)
    if n == 0: break                  # EOF
    if n <  0: fail
    buf_append(&b, chunk, n)
write(1, b.data, b.len)               # one big call, whatever the size
buf_free(&b)
exit(42)
```

## Why buffer the whole thing?

The point isn't the round-trip — `cat` already does that.
The point is *decoupling* the read chunk size from the write
chunk size. Every HTTP client and server that later lands in
this repo has to hold a message with a size it does not know
in advance (until `Content-Length` is seen, or the chunked
terminator arrives). This example is the smallest useful
demonstration that a program can absorb arbitrary-sized input
without allocating a worst-case buffer up front.

## Build and run

```bash
make
echo hello | make run       # prints hello, exit=42
make clean
```

With no input, the read loop hits EOF immediately, the write
is a zero-byte syscall, and libbuf never grows — CI drives
that path via the `pipe_stdin` entry in
`.github/workflows/ci.yml`.

## Next

- Back to [examples/README.md](../README.md).
