# arithmetic

Compute `7 + 5` and return the result as the process exit status.

Paired with [docs/09-arithmetic.md](../../docs/09-arithmetic.md).

## Linux

```bash
nasm -f elf64 add.asm -o add.o
ld add.o -o add
./add ; echo $?
# 12
```

## macOS

```bash
nasm -f macho64 -DMACOS add.asm -o add.o
ld -macos_version_min 11.0 -lSystem \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)" \
   add.o -o add
./add ; echo $?
# 12
```

## What to look at

- No `.data` or `.rodata` — the operands are immediates in `.text`.
- Exit status is the simplest "output channel" while you still have no I/O
  vocabulary.
- The exit code is masked to 8 bits by the shell, so this trick only works for
  values 0–255.
