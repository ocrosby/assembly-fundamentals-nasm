# NASM Fundamentals — Documentation

A progressive walkthrough of x86-64 assembly with NASM. Each guide is intentionally short so a single topic fits on one screen. Read in order, or jump to what you need.

## Getting Started

1. [Installation](01-installation.md) — verify the toolchain.
2. [Hello World](02-hello-world.md) — assemble, link, run.
3. [NASM Syntax](03-syntax.md) — labels, directives, comments.

## Core Concepts

4. [Registers](04-registers.md) — general-purpose, RIP, RFLAGS.
5. [Sections](05-sections.md) — `.text`, `.data`, `.bss`, `.rodata`.
6. [Data Types](06-data-types.md) — `db`, `dw`, `dd`, `dq`, `resb`.
7. [Addressing Modes](07-addressing-modes.md) — immediate, register, memory.

## Operations

8. [Data Movement](08-data-movement.md) — `mov`, `lea`, `xchg`, `push`, `pop`.
9. [Arithmetic](09-arithmetic.md) — `add`, `sub`, `imul`, `idiv`, `inc`, `dec`.
10. [Bitwise & Shifts](10-bitwise.md) — `and`, `or`, `xor`, `not`, `shl`, `shr`.
11. [Comparison & Flags](11-comparison.md) — `cmp`, `test`, RFLAGS bits.

## Control Flow

12. [Jumps](12-jumps.md) — unconditional and conditional branches.
13. [Loops](13-loops.md) — `loop`, counter idioms, `rep`.
14. [Procedures](14-procedures.md) — `call`, `ret`, the System V AMD64 ABI.
15. [The Stack](15-stack.md) — frames, locals, alignment.

## Going Further

16. [System Calls](16-system-calls.md) — macOS vs Linux conventions.
17. [Macros](17-macros.md) — `%define`, `%macro`, conditional assembly.
18. [Linking](18-linking.md) — `ld`, object files, entry points.
19. [Debugging](19-debugging.md) — `lldb` and `gdb` basics.
20. [Cheat Sheet](20-cheat-sheet.md) — x86-64 instructions and registers.

## Extended coverage

- [Floating Point](25-floating-point.md) — scalar single and double
  arithmetic on the SSE `xmm` registers, calling convention, and
  int↔float conversion.

## Appendix

- [References](21-references.md) — external manuals, instruction-set references, and syscall tables.
- [NASM Cheat Sheet](22-nasm-cheat-sheet.md) — assembler-specific syntax: directives, preprocessor, storage sizes, literals.
- [lldb Walkthrough](23-lldb-walkthrough.md) — step-by-step debugging of `examples/07-square` on macOS.
- [gdb Walkthrough](24-gdb-walkthrough.md) — same walkthrough, on Linux.
- [Runnable examples](../examples/) — a constructive sequence of seven small programs paired with chapters 2, 9, 13, and 14.

## Conventions Used in These Guides

- Examples target **x86-64** (long mode), **Intel syntax** (NASM default).
- Platform differences are called out under **macOS** and **Linux** subheadings.
- Code is given as it would be saved in a `.asm` file; assemble with `nasm` and link with `ld` as shown in [Hello World](02-hello-world.md).
