---
name: NASM correctness invariants
description: Semantic invariants (not style) that the NASM Manual mandates for x86-64 sources — case-sensitivity, square brackets for memory, size hints, `default rel`. Violations produce wrong code or relocation errors, not just ugly diffs.
type: project
---

# NASM Correctness Invariants

[`asm-style.md`](asm-style.md) governs formatting: indent, layout,
label placement, comments. This rule governs the four things a NASM
source **must** get right for the assembler to produce what the
reader expects. Every item below is grounded in a specific section
of the [NASM Manual](https://www.nasm.us/doc/); when in doubt, read
the referenced section.

## 1. Case-sensitivity — Manual §2.2.1

NASM is case-sensitive. The manual calls this out as one of the four
core differences from MASM: symbols and labels are distinguished by
case, so `Loop`, `loop`, and `LOOP` are three separate identifiers.

- **Do:** lowercase mnemonics (`mov`, `add`, `syscall`) and register
  names (`rax`, `xmm0`), snake_case for labels
  (`sum_of_squares`, `msg_len`, `.next`).
- **Do not:** rely on case-insensitive matching from other
  assemblers (MASM, GAS). A cross-ported source that "worked
  before" may bind to the wrong symbol under NASM.

## 2. Memory references require square brackets — Manual §2.2.2

The manual is emphatic: `NASM Requires Square Brackets For Memory
References`. Without them, a bare symbol name is an **immediate
address**, not a load.

```nasm
; Correct — load the qword at address `buf` into rax
mov rax, [buf]

; Wrong (silent) — load the *address* of buf into rax
mov rax, buf
```

The bare-symbol form does **not** error; it just does the wrong
thing. Every memory access must be inside `[...]`. When a bare
symbol is intended (as an address value), reach for `lea rax, [buf]`
so the intent is explicit and the code is RIP-relative under
`default rel`.

## 3. Size hints when NASM cannot infer — Manual §3.3, Ch. 4

When one operand is memory and the other is an immediate, NASM
often cannot decide the operand width from context. The manual
recommends explicit size specifiers. The five that matter for
x86-64:

| Size hint | Width   | Typical use               |
|-----------|---------|---------------------------|
| `byte`    | 1 byte  | `mov byte [flag], 0`      |
| `word`    | 2 bytes | rare in 64-bit code       |
| `dword`   | 4 bytes | `mov dword [counter], 0`  |
| `qword`   | 8 bytes | `inc qword [ptr]`         |
| `tword`   | 10 bytes| FPU-only                  |

Rule of thumb: if the assembler could pick a wrong width, name the
width. `inc [counter]` is ambiguous; `inc qword [counter]` is not.

## 4. `default rel` for x86-64 — Manual §8.2.1

`DEFAULT REL / ABS` (Manual §8.2.1) sets the assembler-wide default
between RIP-relative and absolute addressing. On x86-64 you want
RIP-relative for two reasons:

- **Mach-O 64-bit** rejects 32-bit absolute displacements outright,
  so anything using `[symbol]` addressing must be RIP-relative.
- **PIE-linked ELF** (the modern default) prefers RIP-relative for
  the same reason: no relocation entry is needed.

Every `.asm` file in this repo begins with:

```nasm
default rel
```

This is not optional. Omitting it produces a runtime crash in the
best case and a `relocation R_X86_64_32 against ...` linker error in
the worst.

## Enforcement

- Editor-side, the [asm-lsp-config](asm-lsp-config.md) rule pins
  asm-lsp to NASM x86-64 so diagnostics for these four cases fire
  in the buffer.
- CI-side, the `examples-build` job assembles and runs every
  example on macOS (Mach-O 64) and Linux (ELF), so a violation of
  rules 2 or 4 fails immediately.

## See also

- [asm-style](asm-style.md) — indentation, comments, layout.
- [asm-lsp-config](asm-lsp-config.md) — editor-side enforcement.
- [NASM Manual](https://www.nasm.us/doc/) — full reference.
