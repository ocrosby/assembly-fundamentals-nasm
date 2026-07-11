# 24 — static-link

Print `Hello, static archive!` by calling `print_string` from
[`libs/asm/libasm.a`](../../libs/asm/), then exit via
`sys_exit` from the same archive. Builds on
[23-macros](../23-macros/) by introducing one new kind of thing
you can link against: a **static archive** built inside this
repository.

## Introduces

- **Static-archive linking.** `libasm.a` is an `ar` archive of
  `.o` files. When the linker sees an unresolved reference to
  `print_string`, it pulls the object that defines that symbol
  out of the archive and folds it into the final binary. No
  runtime dynamic linker involved — the code lives in the
  executable, exactly as if you had assembled it yourself.
- **Depending on another Make target.** The `Makefile` here
  invokes `make -C ../../libs/asm` before linking so the
  archive is guaranteed to exist. `make -C` is idempotent —
  a fresh clone that has never touched `libs/asm/` still
  builds cleanly.
- **`extern` used for a same-repo symbol.** The `extern
  print_string, sys_exit` declaration is the same syntax that
  20-shared-lib used for `puts` — the difference is where the
  linker finds the definition. Shared library: at run time.
  Static archive: at link time, baked into the binary.

## Contrast with 20-shared-lib

20 linked against `libSystem` / `libc` — code that lives in a
shared library outside the binary and is mapped in at process
startup. This example links against a static archive whose
objects get copied into the binary at link time. The result
is a self-contained executable that has no dynamic-library
dependency for the printing path.

Both models use `extern` in NASM and both work through
`ld`'s symbol table; only the archive format (`.dylib` /
`.so` vs. `.a`) and the resolution timing differ.

## Build and run

```bash
make
make run
make clean
```

Expected: `Hello, static archive!` on stdout, `exit=0`.

## Why this matters going forward

Every future example that needs a real facility — file I/O,
sockets, DNS, formatted output — can now depend on the
matching archive in `libs/`. Later chapters wire in
`libs/io/libio.a` for pread-driven file work,
`libs/sock/libsock.a` for socket calls, and
`libs/resolv/libresolv.a` for DNS lookups, all with the same
`extern` + `$(LIB)` pattern this Makefile establishes.

## Next

- Back to [examples/README.md](../README.md).
