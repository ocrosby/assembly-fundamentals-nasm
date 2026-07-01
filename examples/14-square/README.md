# 07 — square

Call a procedure that squares its argument: `square(7) = 49`,
returned as the exit status. Builds on [13-sum-array](../13-sum-array/)
by extracting a reusable subroutine.

## Introduces

- `call` and `ret`.
- The System V AMD64 calling convention: arg 1 in `rdi`, return value
  in `rax`.
- Leaf functions — no prologue needed because the callee uses only
  caller-saved registers and makes no further calls.
- The 2-operand form of `imul`.

Paired with [docs/14-procedures.md](../../docs/14-procedures.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=49`.

## Next

- [08-stack-frame](../15-stack-frame/) — promote the leaf function
  into one with a full stack frame and stack locals.
