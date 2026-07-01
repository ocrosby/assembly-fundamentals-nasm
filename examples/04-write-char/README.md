# 04 — write-char

Write a single character (`A`) to standard output with `sys_write`.
Builds on [03-add](../03-add/) by introducing the first I/O syscall
in its smallest possible form — a 1-byte buffer in `.rodata`.

## Introduces

- The `write` syscall with a fixed 1-byte payload.
- The 3-arg pattern `rdi=fd`, `rsi=buf`, `rdx=len` shared by every
  I/O syscall that follows.
- The NASM gotcha that `ch`, `cl`, `bh`, etc. are **register**
  names — a label like `ch:` will fail to assemble. This is why
  the byte's label is `letter`, not `ch`.

Paired with [docs/02-hello-world.md](../../docs/02-hello-world.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `A` on stdout, `exit=0`.

## Next

- [05-read-char](../05-read-char/) — the input side of the same
  syscall shape.
