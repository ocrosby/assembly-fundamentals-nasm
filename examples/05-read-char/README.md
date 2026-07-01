# 05 — read-char

Read a single byte from standard input and echo it back. Builds on
[04-write-char](../04-write-char/) by adding `sys_read` and the
`.bss` section — the first *uninitialized* buffer in the sequence.

## Introduces

- The `read` syscall — same 3-arg shape as `write`, but the buffer
  is written to, not read from.
- The `.bss` section for uninitialized data (`resb 1` reserves one
  byte, zero-filled at process start).
- Reading the syscall's return value (`rax` = bytes actually read,
  `0` on EOF, negative on error) and guarding the echo with a
  `test rax, rax` / `jle` so an empty stdin doesn't emit garbage.

Paired with [docs/06-data-types.md](../../docs/06-data-types.md)
(for `.bss`) and [docs/16-system-calls.md](../../docs/16-system-calls.md).

## Build and run

```bash
make
printf 'B' | ./read-char        # after `make` — prints 'B'
make clean
```

Expected on typed input `B`: echoes `B`, `exit=0`. On EOF: no
output, `exit=0`.

## Next

- [06-read-line](../06-read-line/) — same shape, but bigger buffer.
