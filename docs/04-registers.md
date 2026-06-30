# Registers

x86-64 exposes sixteen 64-bit general-purpose registers plus the instruction pointer and flags.

## General-purpose registers

| 64-bit | 32-bit | 16-bit | 8-bit (low) | Conventional role                |
|--------|--------|--------|-------------|----------------------------------|
| `rax`  | `eax`  | `ax`   | `al`        | accumulator, syscall number, return value |
| `rbx`  | `ebx`  | `bx`   | `bl`        | callee-saved                     |
| `rcx`  | `ecx`  | `cx`   | `cl`        | 4th arg (SysV), loop counter     |
| `rdx`  | `edx`  | `dx`   | `dl`        | 3rd arg (SysV), I/O              |
| `rsi`  | `esi`  | `si`   | `sil`       | 2nd arg (SysV), source index     |
| `rdi`  | `edi`  | `di`   | `dil`       | 1st arg (SysV), destination index|
| `rbp`  | `ebp`  | `bp`   | `bpl`       | frame pointer, callee-saved      |
| `rsp`  | `esp`  | `sp`   | `spl`       | stack pointer                    |
| `r8`–`r15` | `r8d`–`r15d` | `r8w`–`r15w` | `r8b`–`r15b` | extra; `r8`/`r9` are 5th/6th args |

Writing to a 32-bit name (e.g., `eax`) **zero-extends** into the 64-bit register. Writing to 16-/8-bit names does not.

## Special registers

- `rip` — instruction pointer; not directly writable, used with `[rel sym]`.
- `rflags` — status bits set by arithmetic and `cmp` (see [Comparison & Flags](11-comparison.md)).

## Calling convention quick view (System V AMD64)

| Arg # | Register |
|-------|----------|
| 1     | `rdi`    |
| 2     | `rsi`    |
| 3     | `rdx`    |
| 4     | `rcx`    |
| 5     | `r8`     |
| 6     | `r9`     |

Return value goes in `rax`. See [Procedures](14-procedures.md) for the full convention.

## Next

- [Sections](05-sections.md)
