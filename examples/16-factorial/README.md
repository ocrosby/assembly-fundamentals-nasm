# 16 — factorial

Compute `factorial(5) = 120` by recursion and return the result as
the exit status. Builds on [15-stack-frame](../15-stack-frame/) by
letting a subroutine call **itself** — recursion in assembly is
just the same `call` / `ret` pattern from 14-square pointed at the
current label.

## Introduces

- **Recursion.** Each recursive call gets its own return address on
  the stack; the recursion unwinds by multiplying return values as
  the frames pop back off.
- **Preserving state across a call with a callee-saved register.**
  The subroutine holds `n` in `rbx` while it calls itself with
  `n-1`. `rbx` is callee-saved (System V AMD64 ABI) so the
  recursive callee is obliged to leave it intact — a lighter
  alternative to the full `rbp`-based stack frame from 15 when the
  function has no locals to spill.
- **The alignment arithmetic of `push rbx`.** One `push` (8 bytes)
  takes the stack from 8-mod-16 at entry to 16-aligned before the
  recursive `call`, matching what the callee expects.

Paired with [docs/14-procedures.md](../../docs/14-procedures.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=120`.

## Next

- [17-macros](../17-macros/) — `%macro` hides the syscall
  boilerplate that shows up in every example so far.
