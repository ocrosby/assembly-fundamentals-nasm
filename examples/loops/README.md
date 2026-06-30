# loops

Two small loop programs paired with [docs/13-loops.md](../../docs/13-loops.md).

| File             | What it does                                       | Exit |
|------------------|----------------------------------------------------|------|
| `countdown.asm`  | Decrement `rcx` from 5 to 0 with `dec`/`jnz`.      | 0    |
| `sum-array.asm`  | Sum a 5-element `int64` array and return the sum.  | 150  |

## Linux

```bash
nasm -f elf64 countdown.asm -o countdown.o && ld countdown.o -o countdown
./countdown ; echo $?

nasm -f elf64 sum-array.asm -o sum-array.o && ld sum-array.o -o sum-array
./sum-array ; echo $?
```

## macOS

```bash
SDK="$(xcrun -sdk macosx --show-sdk-path)"

nasm -f macho64 -DMACOS countdown.asm -o countdown.o
ld -macos_version_min 11.0 -lSystem -syslibroot "$SDK" countdown.o -o countdown
./countdown ; echo $?

nasm -f macho64 -DMACOS sum-array.asm -o sum-array.o
ld -macos_version_min 11.0 -lSystem -syslibroot "$SDK" sum-array.o -o sum-array
./sum-array ; echo $?
```

## What to look at

- `countdown.asm` uses the `dec rcx ; jnz` idiom — fewer instructions than
  `cmp` + jump because `dec` already sets `ZF`.
- `sum-array.asm` loads the array base with `lea rbx, [arr]` first. Mach-O
  forbids 32-bit absolute displacements, so `[arr + rcx*8]` does not assemble
  on macOS; using a base register is portable.
- `arr_len` is computed at assemble time with `equ ($ - arr) / 8`.
