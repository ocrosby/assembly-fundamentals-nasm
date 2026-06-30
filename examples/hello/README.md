# hello

Write `Hello, world!` to standard output and exit cleanly.

Paired with [docs/02-hello-world.md](../../docs/02-hello-world.md).

## Linux

```bash
nasm -f elf64 hello.asm -o hello.o
ld hello.o -o hello
./hello
# Hello, world!
```

## macOS

```bash
nasm -f macho64 -DMACOS hello.asm -o hello.o
ld -macos_version_min 11.0 -lSystem \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)" \
   hello.o -o hello
./hello
# Hello, world!
```

On Apple Silicon the binary runs under Rosetta — install with
`softwareupdate --install-rosetta` if needed.

## What to look at

- `SYS_WRITE` and `SYS_EXIT` numbers swap between Linux and macOS.
- The string lives in `.rodata`; its length is computed at assemble time with
  `equ $ - msg`.
- Both `_start` and `_main` label the same address, so neither linker needs a
  `-e` flag.
