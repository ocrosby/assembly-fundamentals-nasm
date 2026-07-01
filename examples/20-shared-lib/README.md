# 20 — shared-lib

Call `puts("Hello, shared library!")` — delegate the whole
string-write to a shared library (`libSystem` on macOS, `libc` on
Linux) instead of driving `sys_write` by hand. Builds on
[19-struct-ptr](../19-struct-ptr/) by adding one new kind of thing
you can call: a function that lives outside your own object file.

## Introduces

- **`extern` for imported symbols.** The static linker resolves
  the name against a `.dylib` / `.so`; the dynamic linker maps the
  actual shared library into the process at run time.
- **macOS symbol name mangling.** The C `puts` is spelled `_puts`
  in the Mach-O symbol table — a leading underscore. NASM does no
  automatic mangling, so the source names each platform's symbol
  explicitly.
- **Entry point via runtime, not directly.** This example enters
  through `main`/`_main` (not `_start`) and returns with `eax = 0`.
  The runtime that called `main` then calls `exit(0)` for us.
- **Stack alignment for a `call`.** System V AMD64 requires
  `rsp` to be 16-byte aligned at the moment of `call`. `sub rsp, 8`
  before the call pre-aligns; `add rsp, 8` restores. Miss this and
  `puts` may crash inside its own SIMD-using string code.

Paired with [docs/18-linking.md](../../docs/18-linking.md).

## Build and run

```bash
make
make run
make clean
```

Expected: `Hello, shared library!` on stdout, `exit=0`.

## Build differences from the other examples

The Makefile switches the Linux link recipe from `ld` to `gcc`. On
Linux, we need `gcc`'s `crt0` to initialize `libc` before `puts`
runs; a plain `ld` invocation would leave `libc` uninitialized and
`puts` would crash on its first call. On macOS, `ld -lSystem` is
already sufficient — `libSystem` initializes itself when loaded.

The source declares `_main` (macOS) or `main` (Linux) — not
`_start` — because gcc's crt0 calls `main` and `ld -lSystem` also
resolves `_main` as the default entry.

## Next

- [21-cli-args](../21-cli-args/) — read `argc` / `argv` from
  the standard `main` argument registers and observe what the
  runtime that just called us knows about our command line.
