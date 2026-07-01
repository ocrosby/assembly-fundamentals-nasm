# 22 — struct-return

Call `make_rect(10, 20, 30, 40)` — a subroutine that constructs a
`struct rect { int64_t x, y, w, h; }` (32 bytes) and returns it
**by value** to the caller. Because the struct is larger than 16
bytes, the System V AMD64 ABI silently switches to a *return by
hidden pointer* convention. Builds on
[21-cli-args](../21-cli-args/) by adding a new twist to the
calling convention that isn't visible from the C source at all —
the compiler (or, here, the assembly programmer) has to know.

The exit status is `x + y + w + h = 100`. One number that proves
every field was stored by the callee and read back by the caller.

## Introduces

- **Returning a big struct by value.** When the return type is
  larger than can fit in `rax` + `rdx` (i.e. more than 16 bytes),
  the ABI hides an extra argument at position 1: a pointer to
  storage the *caller* reserved for the return value.
- **The programmer-visible args shift right by one.**
  `make_rect(x, y, w, h)` in C receives four args, but in assembly
  five registers are in play: `rdi` = hidden pointer, `rsi` = x,
  `rdx` = y, `rcx` = w, `r8` = h. The `x` argument is **not** in
  `rdi` because `rdi` is spoken for.
- **The callee returns the hidden pointer unchanged.** `rax`
  matches the pointer the caller handed in via `rdi`. Callers can
  chain `f().g` off the returned value.
- **Frame-pointer allocation of the return slot.** The classic
  `push rbp` / `mov rbp, rsp` / `sub rsp, 32` prologue reserves
  the 32 bytes; `[rbp - 32 + OFFSET]` addresses each field.

Paired with [docs/14-procedures.md](../../docs/14-procedures.md)
and [docs/15-stack.md](../../docs/15-stack.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=100` (= `10 + 20 + 30 + 40`).

## Build differences from most examples

Same per-platform recipe as [20-shared-lib](../20-shared-lib/) and
[21-cli-args](../21-cli-args/): macOS uses `ld -lSystem`, Linux
uses `gcc` as the driver. Entry point is `main`/`_main`; the
runtime calls us, we return a status in `eax`, and the runtime
calls `exit()` for us. No shared libraries are actually called
from this example — the ABI choice comes purely from having a
`main` entry.

## Next

- [23-macros](../23-macros/) — `%macro` hides the syscall
  boilerplate that shows up in every example so far.
