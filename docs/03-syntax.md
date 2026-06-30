# NASM Syntax

NASM uses **Intel syntax**: `instruction destination, source`.

## Anatomy of a line

```nasm
label:
    mnemonic operand1, operand2 ; comment
```

- **Label** — optional name for the current address; ends in `:`.
- **Mnemonic** — the instruction (`mov`, `add`, `jmp`, …).
- **Operands** — comma-separated; destination is first.
- **Comment** — everything after `;` is ignored.

## Identifiers and case

- Labels and identifiers are **case-sensitive**: `Loop` and `loop` differ.
- Instructions and register names are conventionally lowercase.
- Local labels start with `.` and are scoped to the previous non-local label:

```nasm
main:
    mov rcx, 10
.next:
    dec rcx
    jnz .next
```

## Numeric literals

| Form        | Example          |
|-------------|------------------|
| Decimal     | `42`             |
| Hex         | `0x2a`, `2ah`    |
| Octal       | `52o`, `052q`    |
| Binary      | `0b101010`, `101010b` |
| Character   | `'A'` (= `0x41`) |

## Directives you will see often

| Directive  | Purpose                                        |
|------------|------------------------------------------------|
| `global`   | Export a symbol so the linker can see it.      |
| `extern`   | Reference a symbol defined elsewhere.          |
| `section`  | Switch to `.text`, `.data`, `.bss`, `.rodata`. |
| `equ`      | Define a compile-time constant.                |
| `default`  | Set defaults (e.g., `default rel`).            |

## Strings

NASM accepts single, double, and backquoted strings. Only **backquoted** strings interpret escapes like `\n`:

```nasm
a: db "hello"                   ; literal h e l l o
b: db `hello\n`                 ; literal h e l l o 0x0a
```

## Next

- [Registers](04-registers.md)
