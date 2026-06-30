# 01 — exit-zero

Ask the OS to terminate this process with status `0`. The smallest program
that does anything observable.

## Introduces

- The `.text` section.
- Entry symbols `_start` (Linux) and `_main` (macOS).
- The `syscall` instruction: number in `rax`, args in `rdi`/`rsi`/`rdx`, …
- Zeroing a register with `xor reg, reg`.

## Build and run

```bash
make            # assemble + link
make run        # build (if needed) then execute, prints exit status
make clean      # remove the .o and the executable
```

Expected: `exit=0`.

## Next

- [02-exit-status](../02-exit-status/) — return a chosen value through the exit status.
