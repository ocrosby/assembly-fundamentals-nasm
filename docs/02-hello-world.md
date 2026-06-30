# Hello World

The smallest complete program: write a string to stdout and exit.

## Source — `hello.asm`

```nasm
global _start

section .text
_start:
    mov rax, 1               ; sys_write
    mov rdi, 1               ; fd = stdout
    mov rsi, msg             ; buffer
    mov rdx, msg_len         ; length
    syscall

    mov rax, 60              ; sys_exit
    xor rdi, rdi             ; status = 0
    syscall

section .rodata
msg: db "Hello, world!", 10
msg_len: equ $ - msg
```

The example above uses Linux syscall numbers. On macOS, see [System Calls](16-system-calls.md).

## Build and run — Linux

```bash
nasm -f elf64 hello.asm -o hello.o
ld hello.o -o hello
./hello
# Hello, world!
```

## Build and run — macOS

macOS programs link against `libSystem` and use a different entry point. See [System Calls](16-system-calls.md) and [Linking](18-linking.md) for the full story.

```bash
nasm -f macho64 hello.asm -o hello.o
ld -macos_version_min 11.0 -lSystem -o hello hello.o \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)"
./hello
```

## Runnable

- [examples/04-hello/](../examples/04-hello/) — `make && make run`. Cross-platform
  source with the syscall numbers swapped by `%ifdef MACOS`.

## Next

- [NASM Syntax](03-syntax.md)
