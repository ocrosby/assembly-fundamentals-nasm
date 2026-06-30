# Runnable Examples

Each subdirectory holds a small, complete program referenced by a chapter in
[../docs/](../docs/). Sources use NASM with Intel syntax and target x86-64. A
short `%ifdef MACOS` block at the top of each file selects the right syscall
numbers per platform; both `_start` (Linux default) and `_main` (macOS default)
are declared as entry symbols so neither linker needs a `-e` flag.

## Build prerequisites

| Platform                | Tools                                                          |
|-------------------------|----------------------------------------------------------------|
| Linux (x86-64)          | NASM, `ld` (binutils)                                           |
| macOS (Intel)           | NASM, `ld` from Xcode Command Line Tools                        |
| macOS (Apple Silicon)   | NASM, `ld` from Xcode Command Line Tools, **Rosetta 2 installed** |

Install Rosetta on Apple Silicon with `softwareupdate --install-rosetta` if it
is not already running. The resulting x86-64 Mach-O binaries are translated
transparently at run time.

## Build pattern

From the repository root, the per-example READMEs show the exact commands. They
all follow the same template:

```bash
# Linux
nasm -f elf64 examples/<topic>/<name>.asm -o examples/<topic>/<name>.o
ld examples/<topic>/<name>.o -o examples/<topic>/<name>
./examples/<topic>/<name>

# macOS (Intel or Apple Silicon under Rosetta)
nasm -f macho64 -DMACOS examples/<topic>/<name>.asm -o examples/<topic>/<name>.o
ld -macos_version_min 11.0 -lSystem \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)" \
   examples/<topic>/<name>.o -o examples/<topic>/<name>
./examples/<topic>/<name>
```

Build artifacts (`*.o` and the unsuffixed executables) are gitignored.

## Index

| Example                                       | Returns | Chapter                             |
|-----------------------------------------------|---------|-------------------------------------|
| [hello/](hello/)                              | exit 0  | [docs/02](../docs/02-hello-world.md) |
| [arithmetic/](arithmetic/)                    | exit 12 | [docs/09](../docs/09-arithmetic.md) |
| [loops/countdown](loops/)                     | exit 0  | [docs/13](../docs/13-loops.md)      |
| [loops/sum-array](loops/)                     | exit 150| [docs/13](../docs/13-loops.md)      |
| [procedures/](procedures/)                    | exit 49 | [docs/14](../docs/14-procedures.md) |

Read the exit status with `echo $?` immediately after running, since most
examples report their result that way.
