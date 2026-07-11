# 23 — macros

Use `%macro` to hide the sys_write and sys_exit boilerplate, then
write `Hello, world!` and exit with status 42 using just three lines
of body code in `_main`. Builds on [22-struct-return](../22-struct-return/)
by introducing NASM's preprocessor macros.

## Introduces

- Multi-line `%macro` definitions with a fixed argument count.
- Positional argument substitution inside a macro body (`%1`, `%2`).
- How macros make the platform-branching syscall numbers (`%ifdef
  MACOS`) invisible at the call site.

Paired with [docs/17-macros.md](../../docs/17-macros.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `Hello, world!` on stdout, `exit=42`.

## Next

- [24-static-link](../24-static-link/) — link an example against
  a static archive built in this repo (`libs/asm/libasm.a`)
  instead of a shared library. Sets up every later chapter to
  depend on the `libs/` archives.
