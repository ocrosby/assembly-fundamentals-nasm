# 03 — add

Compute `7 + 5` in registers and return the result (`12`) as the exit
status. Builds on [02-exit-status](../02-exit-status/) by *computing* the
status instead of moving an immediate.

## Introduces

- The `add reg, reg` instruction.
- One register acting as both source and destination.

Paired with [docs/09-arithmetic.md](../../docs/09-arithmetic.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=12`.

## Next

- [04-hello](../04-hello/) — write to standard output instead of just
  exiting.
