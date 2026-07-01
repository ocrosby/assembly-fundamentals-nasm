# 17 — stack-args

Call `sum8(1, 2, 3, 4, 5, 6, 7, 8) = 36` and return the sum as the
exit status. Builds on [16-factorial](../16-factorial/) by passing
more arguments than the System V AMD64 ABI reserves register slots
for — the seventh and eighth arguments travel on the **stack**.

## Introduces

- **Six-register cap.** SysV AMD64 provides exactly six integer arg
  registers: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`. Any function
  with more than six integer args needs another channel.
- **Right-to-left stack push.** The caller pushes the extra args
  in *reverse order* (arg 8 first, then arg 7) so that arg 7 ends
  up at the lower address — the same order a C programmer would
  expect if they thought of the stack as an array.
- **Callee-side addressing.** Inside the callee's `rbp`-based
  frame, the stack args live at `[rbp + 16]` (arg 7) and
  `[rbp + 24]` (arg 8). The math: `[rbp + 0]` is the saved caller
  `rbp`, `[rbp + 8]` is the return address, and everything above
  that is caller-owned.
- **Caller cleanup.** The caller is responsible for removing the
  stack args after `call` — `add rsp, 16` pops both back off.

Paired with [docs/14-procedures.md](../../docs/14-procedures.md)
and [docs/15-stack.md](../../docs/15-stack.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=36`.

## Next

- [18-divmod](../18-divmod/) — return two values from a
  subroutine at once, using both of the ABI's return-value slots
  (`rax` and `rdx`).
