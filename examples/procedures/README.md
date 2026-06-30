# procedures

Call a `square` procedure with `rdi = 7` and return `49` as the exit status.

Paired with [docs/14-procedures.md](../../docs/14-procedures.md).

## Linux

```bash
nasm -f elf64 square.asm -o square.o
ld square.o -o square
./square ; echo $?
# 49
```

## macOS

```bash
nasm -f macho64 -DMACOS square.asm -o square.o
ld -macos_version_min 11.0 -lSystem \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)" \
   square.o -o square
./square ; echo $?
# 49
```

## What to look at

- The call follows the System V AMD64 ABI: arg 1 goes in `rdi`, the return
  value comes back in `rax`.
- `square` is a leaf function — it makes no further calls, allocates no
  locals, and uses only caller-saved registers, so no prologue is needed.
- `call square` pushes the return address; `ret` pops it. The `_main`/`_start`
  block balances exactly one `call`.
