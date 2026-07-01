# NASM Cheat Sheet

The Netwide Assembler's syntax at a glance. For instruction and register
reference, see [Cheat Sheet](20-cheat-sheet.md).

## Command line

```bash
nasm -f macho64 -DMACOS file.asm -o file.o    # macOS
nasm -f elf64            file.asm -o file.o   # Linux
nasm -f win64            file.asm -o file.obj # Windows
nasm -g -F dwarf ...                          # embed DWARF debug info
nasm -Dname=value ...                         # define preprocessor symbol
nasm -Iinclude/ ...                           # add include search path
```

## Sections and directives

```nasm
default rel                   ; RIP-relative addressing by default
bits 64                       ; force 64-bit mode (implied by macho64/elf64)
global _main, _start          ; export symbols
extern printf                 ; import symbol from another object
section .text                 ; code
section .data                 ; initialized read/write data
section .rodata               ; initialized read-only data
section .bss                  ; uninitialized (zero-filled) data
```

## Preprocessor

Textual substitution, evaluated before assembly:

```nasm
%define SYS_EXIT 0x2000001    ; textual constant

%ifdef MACOS                  ; conditional block
%else
%endif

%include "syscalls.inc"       ; textually include a file

%macro exit 1                 ; 1-argument multi-line macro
    mov rdi, %1
    mov rax, SYS_EXIT
    syscall
%endmacro
```

See [Macros](17-macros.md) for `%undef`, `%if`, `%rep`, and nested macros.

## Data and storage

Initialized (in `section .data` or `.rodata`):

| Directive | Size    | Example                    |
|-----------|---------|----------------------------|
| `db`      | 1 byte  | `msg: db "Hi", 10`         |
| `dw`      | 2 bytes | `nums: dw 100, 200`        |
| `dd`      | 4 bytes | `flag: dd 0xdeadbeef`      |
| `dq`      | 8 bytes | `ptrs: dq addr1, addr2`    |

Uninitialized (in `section .bss`):

| Directive | Size    | Example              |
|-----------|---------|----------------------|
| `resb`    | 1 byte  | `buf: resb 64`       |
| `resw`    | 2 bytes | `words: resw 32`     |
| `resd`    | 4 bytes | `dwords: resd 16`    |
| `resq`    | 8 bytes | `qwords: resq 8`     |

Assemble-time constants:

```nasm
buf_size equ 64               ; label = expression
msg_len  equ $ - msg          ; computed at assemble time
```

## Labels

```nasm
main:                         ; global label
.loop:                        ; local — scoped to the previous global label
    jmp .loop                 ; short reference inside main
    jmp main.loop             ; qualified access from another scope
```

## Literals

| Form    | Example                    |
|---------|----------------------------|
| Decimal | `42`                       |
| Hex     | `0xff` / `0FFh` / `ffh`    |
| Octal   | `52o` / `52q`              |
| Binary  | `0b1010` / `1010b`         |
| Char    | `'A'` = `0x41`             |

Strings:

- `"hello"` — literal bytes only.
- `'hello'` — same as double quotes.
- `` `hello\n` `` — **backticks** interpret escapes (`\n`, `\t`, `\0`, `\xNN`).

## Special symbols

- `$`  — current address during assembly.
- `$$` — start address of the current section.
- `%1`, `%2`, … — macro argument N inside a `%macro` body.

## See also

- [Cheat Sheet](20-cheat-sheet.md) — x86-64 instructions and registers.
- [Macros](17-macros.md) — chapter on the preprocessor.
- [Index](README.md)
