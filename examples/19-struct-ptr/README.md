# 19 — struct-ptr

Pass a `struct point` to a subroutine by pointer. The callee
mutates both fields through the pointer, and the caller reads the
mutated values back. Builds on
[18-divmod](../18-divmod/) by moving from "many arg registers" to
"one pointer, many fields at offsets."

The point starts at `(10, 20)`. `translate(&pt, 3, 4)` moves it to
`(13, 24)`. The exit status is `pt.x + pt.y = 37` — one number
that proves the pointer reached the callee, the callee mutated
both fields, and the caller read the mutated fields back.

## Introduces

- **Structs in NASM.** No `struct` keyword — a struct is just
  contiguous memory. This example uses `equ` constants
  (`POINT_X = 0`, `POINT_Y = 8`) as field offsets, giving reads and
  writes a readable name even though the underlying encoding is
  `[reg + immediate]`.
- **Passing by pointer.** One address in `rdi` reaches the callee
  instead of packing every field into a separate register. Scales
  to structs of any size, and is how C compilers pass anything
  bigger than 16 bytes on this ABI.
- **Mutation through a pointer.** The callee has no return value;
  side effects on `*p` are how it communicates back. The caller
  reads the mutated fields via the same pointer.
- **The `add [mem], reg` RMW form.** One instruction reads the
  memory operand, adds the register, and writes the result back.
  No intermediate register needed.

Paired with [docs/07-addressing-modes.md](../../docs/07-addressing-modes.md)
and [docs/14-procedures.md](../../docs/14-procedures.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=37` (= `13 + 24`, the mutated `pt.x + pt.y`).

## Next

- [20-shared-lib](../20-shared-lib/) — call a function from
  a shared library (`puts` from libc) instead of driving the
  write syscall by hand.
