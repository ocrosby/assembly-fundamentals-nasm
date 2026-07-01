# 08 — stack-frame

Call a function that uses a full frame-pointer prologue and stores
two intermediate squares as stack locals. Builds on
[14-square](../14-square/) by promoting the leaf function into one
with a proper stack frame.

Computes `3*3 + 4*4 = 25` and returns it as the exit status.

## Introduces

- The `push rbp` / `mov rbp, rsp` / `sub rsp, N` prologue.
- Addressing stack locals as `[rbp - offset]`.
- The matching `mov rsp, rbp` / `pop rbp` epilogue.
- 16-byte-aligned local space so `rsp` stays 16-byte aligned across
  the frame.

Paired with [docs/15-stack.md](../../docs/15-stack.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=25`.

## Next

- [09-macros](../16-macros/) — hide the syscall boilerplate behind
  `%macro`.
