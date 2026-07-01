# Linking

NASM produces an **object file**; the linker combines one or more object files into an **executable**.

## Output formats

```bash
nasm -f macho64  file.asm -o file.o     # macOS
nasm -f elf64    file.asm -o file.o     # Linux
nasm -f win64    file.asm -o file.obj   # Windows
```

The format flag must match the host OS — an ELF object will not link on macOS.

## Entry points

| Platform | Default entry symbol |
|----------|----------------------|
| macOS    | `_main`              |
| Linux    | `_start`             |

The entry symbol must be marked `global`. If you call `libc`, use `_main` everywhere and let the C runtime call you after it sets up its state.

## Linking — macOS

macOS does not support fully freestanding ELF-style linking — you must link `libSystem`:

```bash
ld -macos_version_min 11.0 \
   -lSystem \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)" \
   -o file file.o
```

Or, more concisely with `clang`:

```bash
clang file.o -o file
```

## Linking — Linux

Freestanding (no libc):

```bash
ld file.o -o file
```

With libc:

```bash
gcc file.o -o file -no-pie
```

`gcc` handles startup files and `libc` for you. Use `-no-pie` if your example assumes absolute addressing; modern examples should use `default rel` and `lea ... [rel ...]` instead.

## Inspecting the result

```bash
file ./prog                     # what kind of binary?
nm ./prog                       # symbol table
otool -tV ./prog                # disassemble (macOS)
objdump -d ./prog               # disassemble (Linux)
```

## Runnable

- [examples/20-shared-lib/](../examples/20-shared-lib/) — call
  `puts` from `libSystem`/`libc`, demonstrating `extern`, macOS
  symbol underscore mangling, and the switch from `ld` to `gcc`
  on Linux so `libc` gets initialized before the call.

## Common errors

- `undefined reference to '_start'` → entry symbol missing `global`, or wrong name for the platform.
- `relocation R_X86_64_32 against ...` → non-PIE addressing in a PIE link; add `default rel`.
- macOS: `ld: dynamic main executables must link with libSystem.dylib` → add `-lSystem`.

## Next

- [Debugging](19-debugging.md)
