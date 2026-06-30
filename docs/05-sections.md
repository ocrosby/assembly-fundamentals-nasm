# Sections

A NASM program is partitioned into **sections**. Each section ends up in a region of the object file with specific permissions and initialization rules.

## The four you will use

| Section   | Contents                          | Initialized? | Writable? | Executable? |
|-----------|-----------------------------------|--------------|-----------|-------------|
| `.text`   | machine code                      | yes          | no        | yes         |
| `.rodata` | read-only constants (strings)     | yes          | no        | no          |
| `.data`   | initialized read/write data       | yes          | yes       | no          |
| `.bss`    | uninitialized data (zero-filled)  | no           | yes       | no          |

## Switching sections

```nasm
            section .text
            global  _start
_start:     mov     rax, [counter]      ; read from .data
            mov     rbx, [scratch]      ; read from .bss

            section .data
counter:    dq      1                   ; 8-byte int = 1

            section .bss
scratch:    resq    1                   ; reserve 8 bytes, zeroed

            section .rodata
greeting:   db      "hi", 0
```

## Why `.bss` is special

`.bss` does not take up space in the object file; the loader zeros it at program start. Use it for buffers and uninitialized globals — never put `db 0` in `.data` when `resb 1` in `.bss` will do.

## Position-independent code

Modern macOS and most Linux toolchains expect position-independent addressing. Tell NASM to default to RIP-relative:

```nasm
            default rel
            section .text
            lea     rsi, [msg]          ; really [rip + msg]
```

## Next

- [Data Types](06-data-types.md)
