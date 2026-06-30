# 04 — hello

Write `Hello, world!` to standard output, then exit. Builds on
[03-add](../03-add/) by adding a second syscall (`write`) and a piece
of read-only data.

## Introduces

- The `write` syscall.
- The `.rodata` section.
- Taking a label's address with `lea`.
- Assemble-time string length: `msg_len equ $ - msg`.

Paired with [docs/02-hello-world.md](../../docs/02-hello-world.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `Hello, world!` on stdout, `exit=0`.

## Next

- [05-countdown](../05-countdown/) — introduce control flow.
