# Macros

NASM has a powerful preprocessor that runs before assembly. It is your main tool for keeping examples short and readable.

## `%define` — single-line substitution

```nasm
%define SYS_WRITE       1
%define STDOUT          1

    mov rax, SYS_WRITE
    mov rdi, STDOUT
```

`%define` is textual and case-sensitive. Prefer it over `equ` when the value is conceptually a *name* rather than an *address-time constant*.

## `equ` — assemble-time constant

```nasm
buf_len equ 64
```

Bound to a label and known to the assembler as a value with a section.

## `%macro` — multi-line substitution

```nasm
%macro write 2
    mov rax, 1
    mov rdi, 1
    mov rsi, %1
    mov rdx, %2
    syscall
%endmacro

    write msg, msg_len
```

`%1`, `%2`, … are the macro arguments; the `2` after `%macro` is the argument count.

## Conditional assembly

```nasm
%ifdef LINUX
    mov rax, 60
%else
    mov rax, 0x2000001
%endif
    xor rdi, rdi
    syscall
```

Pass `-DLINUX` on the NASM command line to set the symbol.

## Include files

Split shared definitions into their own file and include them:

```nasm
%include "syscalls.inc"
```

## When to reach for a macro

- Repeated boilerplate (e.g., a `write` syscall used in five examples).
- Platform branching (macOS vs Linux).
- Naming magic numbers so a reader doesn't have to look them up.

Resist using macros to invent a tiny private language; they hide what the CPU actually does, which is the whole point of writing assembly.

## Runnable

- [examples/16-macros/](../examples/16-macros/) — `%macro` hides the `sys_write` and `sys_exit` boilerplate so `_main` reads as three high-level lines.

## Next

- [Linking](18-linking.md)
