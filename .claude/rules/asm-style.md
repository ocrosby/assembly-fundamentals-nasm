---
name: NASM source style
description: NASM .asm sources use 4-space indent, labels on their own line, and instructive inline comments explaining intent.
type: project
---

# NASM Source Style

NASM `.asm` files in this repo follow a uniform style optimized for
**reading and learning**, not for screen real estate. The repository
is educational; every example will be read by someone who has never
seen the instructions before.

## Indentation

- **4 spaces** of indent for instructions and pseudo-ops inside a
  section. Enforced by `.editorconfig` at the repository root.
- **Column 0** for file-level directives (`%define`, `%ifdef`,
  `default`, `global`, `extern`, `equ`, `section`) and for labels.
- Do not use tabs in `.asm` files.

## Labels

- Place every label on its own line. Do not put `label: mov ...` on
  the same line — it forces the eye to scan two columns at once and
  hides the label when the line is otherwise long.

```nasm
; ✅ preferred
_start:
_main:
    mov rax, SYS_EXIT
```

```nasm
; ❌ avoid
_main:      mov     rax, SYS_EXIT
```

## Spacing within an instruction

- Exactly one space between the mnemonic and its operands:
  `mov rax, 1`.
- Exactly one space after each comma between operands.
- **Do not** column-align operands across multiple lines. Columnar
  alignment ages poorly when one operand changes width and forces
  noisy whitespace-only diffs.

## Instructive comments

Every non-trivial line gets a short inline comment explaining the
**intent** — what role the value plays at that point — not the
mechanics of the opcode.

```nasm
xor rdi, rdi            ; exit status = 0
mov rcx, arr_len        ; loop bound
syscall                 ; sys_write(stdout, msg, len)
```

```nasm
xor rdi, rdi            ; xor rdi with itself          ← restates opcode, do not write
mov rcx, arr_len        ; move arr_len into rcx        ← restates opcode, do not write
```

### Comment guidance

- Comments name the **role** of a value: `; loop counter`,
  `; base pointer`, `; arg 1`, `; result`, `; exit status`.
- Idiomatic patterns get a one-time mention when first introduced:
  `; zero rax (faster than mov rax, 0)`. Subsequent uses do not.
- Calling-convention details belong on the boundary instructions
  (the `mov rdi, ...` before a `call`, the `ret` of a callee), not
  on every line of a procedure body.
- `syscall` always gets a comment naming the call:
  `; sys_exit(rdi)`.
- Comments live at column 25–33 when practical, but never at the
  cost of breaking a line of code across two physical lines.

## Editor support

`.editorconfig` sets `indent_style = space` and `indent_size = 4` for
`*.asm`. Modern editors apply this automatically; for editors that do
not read EditorConfig, configure manually.
