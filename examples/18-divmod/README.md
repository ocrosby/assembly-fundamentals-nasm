# 18 — divmod

Call `divmod(17, 5)` — computes the quotient (3) and the remainder
(2) in a single subroutine and returns **both** to the caller.
Builds on [17-stack-args](../17-stack-args/) by using **two** of
the ABI's return-value slots at once.

The exit status combines both returns: `quotient * 10 + remainder
= 32`. One number, two proofs that both halves survived the call.

## Introduces

- **Returning two values from a subroutine.** The System V AMD64
  ABI reserves both `rax` and `rdx` as return-value slots (their
  original purpose is holding the two halves of a 128-bit integer
  return). This example uses them for two independent 64-bit
  values.
- **The `div` instruction as a two-output op.** `div rsi` divides
  the 128-bit dividend in `rdx:rax` by `rsi`, leaving the quotient
  in `rax` and the remainder in `rdx` — the CPU produces both
  results in a single cycle, and the ABI already has a place to
  put each half.
- **Unsigned-division setup.** `xor rdx, rdx` zeroes the upper
  half of the dividend before `div`, so the 128-bit input becomes
  just the 64-bit value already in `rax`. Signed inputs would use
  `cqo` + `idiv` instead.

Paired with [docs/09-arithmetic.md](../../docs/09-arithmetic.md)
(for `div` semantics) and
[docs/14-procedures.md](../../docs/14-procedures.md) (for the
calling convention).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=32` (= `3 * 10 + 2`, showing that both the
quotient in `rax` and the remainder in `rdx` came back intact).

## Next

- [19-macros](../19-macros/) — `%macro` hides the syscall
  boilerplate that shows up in every example so far.
