# 06 — sum-array

Sum a 5-element `int64` array (10 + 20 + 30 + 40 + 50 = 150) and
return the sum as the exit status. Builds on
[12-countdown](../12-countdown/) by adding memory.

## Introduces

- The `.data` section (initialized read-write data).
- Indexed addressing: `[base + index * scale]`.
- The load-base-pointer-then-index pattern: `lea rbx, [arr]` followed
  by `[rbx + rcx*8]`. Mach-O 64-bit forbids 32-bit absolute
  displacements, so going through a base register keeps the source
  portable.

Paired with [docs/13-loops.md](../../docs/13-loops.md) and
[docs/07-addressing-modes.md](../../docs/07-addressing-modes.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=150`.

## Next

- [07-square](../14-square/) — factor a calculation into a procedure.
