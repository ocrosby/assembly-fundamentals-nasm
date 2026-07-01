# Hello World

The smallest complete program: write a string to stdout and exit.

## Source — `hello.asm`

```nasm
%ifdef MACOS
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    mov rax, SYS_WRITE               ; syscall number
    mov rdi, 1                       ; arg 1: fd = stdout
    lea rsi, [msg]                   ; arg 2: buffer
    mov rdx, msg_len                 ; arg 3: length
    syscall                          ; sys_write(stdout, msg, msg_len)

    mov rax, SYS_EXIT
    xor rdi, rdi                     ; status = 0
    syscall                          ; sys_exit(0)

section .rodata
msg: db "Hello, world!", 10
msg_len: equ $ - msg
```

The `%ifdef MACOS` block picks the right syscall numbers per platform, and both `_start` and `_main` are declared as globals so the source works with either linker's default entry symbol. See [System Calls](16-system-calls.md) for the syscall table.

## Build and run — macOS

macOS programs link against `libSystem`. See [Linking](18-linking.md) for the full story.

```bash
nasm -f macho64 -DMACOS hello.asm -o hello.o
ld -macos_version_min 11.0 -lSystem -o hello hello.o \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)"
./hello
# Hello, world!
```

On Apple Silicon the resulting x86-64 binary runs under Rosetta; install with `softwareupdate --install-rosetta` if it is not already present.

## Build and run — Linux

```bash
nasm -f elf64 hello.asm -o hello.o
ld hello.o -o hello
./hello
# Hello, world!
```

## Runnable

- [examples/04-hello/](../examples/04-hello/) — this same program with a `Makefile` that auto-detects the platform. `make && make run`.

## Next

- [NASM Syntax](03-syntax.md)
