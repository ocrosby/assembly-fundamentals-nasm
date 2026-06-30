# Data Types

NASM has no high-level types — only sized cells. You choose width with a directive.

## Reserving initialized data

| Directive | Width   | Common name | Example                   |
|-----------|---------|-------------|---------------------------|
| `db`      | 1 byte  | byte        | `db 0x41, 'B', 67`        |
| `dw`      | 2 bytes | word        | `dw 1000`                 |
| `dd`      | 4 bytes | dword       | `dd 0xdeadbeef`           |
| `dq`      | 8 bytes | qword       | `dq 1, 2, 3`              |
| `dt`      | 10 bytes| tword       | `dt 3.14159265358979e0`   |

## Reserving uninitialized data (in `.bss`)

| Directive | Width   | Example          |
|-----------|---------|------------------|
| `resb`    | 1 byte  | `resb 64`        |
| `resw`    | 2 bytes | `resw 32`        |
| `resd`    | 4 bytes | `resd 16`        |
| `resq`    | 8 bytes | `resq 8`         |

## Size hints in instructions

When the size cannot be inferred from a register, prefix the memory operand:

```nasm
            mov     byte  [buf], 1
            mov     word  [count], 1000
            mov     dword [flag], 0
            mov     qword [ptr], rax
```

## Strings and arrays

```nasm
            section .data
name:       db      "Ada", 0            ; NUL-terminated
nums:       dd      1, 2, 3, 4, 5       ; 5-element int32 array
nums_len:   equ     ($ - nums) / 4      ; computed at assemble time
```

`$` is the current address; `$$` is the start of the current section.

## Next

- [Addressing Modes](07-addressing-modes.md)
