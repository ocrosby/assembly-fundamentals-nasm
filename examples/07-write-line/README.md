# 07 — write-line

Write a complete line — `Hello, world!\n` — to standard output.
This is the classic first program of the tutorial world; here it
serves as the output-side line primitive that pairs with
[06-read-line](../06-read-line/).

## Introduces

- A message in `.rodata` (read-only initialized data).
- `lea rsi, [msg]` — take the address of a symbol, RIP-relative
  under `default rel`.
- The `equ $ - msg` idiom that computes the message length at
  assemble time.

Paired with [docs/02-hello-world.md](../../docs/02-hello-world.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `Hello, world!` on stdout, `exit=0`.

## Next

- [08-echo-loop](../08-echo-loop/) — combine `read` and `write` in
  a loop, until EOF.
