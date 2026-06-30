# 02 — exit-status

Exit with status `42` so the shell can read the value back. Builds on
[01-exit-zero](../01-exit-zero/) by parameterizing the exit code.

## Introduces

- Loading an immediate value into a register: `mov rdi, 42`.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- [03-add](../03-add/) — do arithmetic before exiting.
