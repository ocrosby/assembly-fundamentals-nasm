# 05 — countdown

Decrement `rcx` from `5` to `0`, then exit. No I/O — the loop *is*
the point. Builds on [04-hello](../04-hello/) by adding control flow
without taking on any new I/O surface.

## Introduces

- Local labels (the `.next` form, scoped to the previous global label).
- Conditional jumps.
- The `dec` / `jnz` loop idiom — fewer instructions than
  `cmp reg, 0` + jump because `dec` already updates the zero flag.

Paired with [docs/13-loops.md](../../docs/13-loops.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=0`.

## Next

- [06-sum-array](../06-sum-array/) — combine the loop with memory.
