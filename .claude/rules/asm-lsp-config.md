---
name: asm-lsp Configuration
description: All .asm files are NASM Intel syntax for x86-64; .asm-lsp.toml pins the LSP; do not change source to silence misconfigured tools.
type: project
---

# asm-lsp Configuration

Every `.asm` file in this repo is **NASM Intel syntax targeting x86-64**.
That contract is enforced for editors by `.asm-lsp.toml` at the repo
root, which pins
[asm-lsp](https://github.com/bergercookie/asm-lsp) to
`assembler = "nasm"` and `instruction_set = "x86-64"`. Without this
file, asm-lsp falls back to GAS / AT&T syntax (and on Apple Silicon also
to the `arm64` instruction set), and every NASM preprocessor directive,
every NASM assembler directive, and every Intel-syntax operand is
flagged as a phantom error.

## When LSP diagnostics look wrong

If `asm-lsp` reports any of these on freshly-written, otherwise-valid
NASM, the **tool is misconfigured**, not the source:

- "unexpected token at start of statement" on lines starting with
  `%define`, `%ifdef`, `%else`, `%endif`, `%macro`, `%endmacro`.
- "unrecognized instruction mnemonic" on `default`, `global`, `section`,
  `extern`, `equ`, or even on real x86-64 instructions like `syscall`.
- "invalid operand for instruction" on plain Intel-syntax operands such
  as `mov rdi, 42` or `lea rsi, [msg]`.

The fix is **always** in `.asm-lsp.toml`. Do not change the source files
to match a misconfigured tool: do not switch to AT&T syntax, do not add
per-file pragmas, do not insert inline disables, do not delete the
`%ifdef MACOS` blocks. The source is correct by design.

## Verifying the config is loaded

When running inside Neovim, query the live LSP for the open buffer:

```bash
nvim --server "$NVIM" --remote-expr \
  'luaeval("vim.json.encode(vim.diagnostic.get(vim.fn.bufnr(_A)))", "examples/01-exit-zero/exit-zero.asm")'
```

Zero diagnostics on a known-good example means the config is loaded.
If you change `.asm-lsp.toml`, restart the LSP client:

```bash
nvim --server "$NVIM" --remote-expr \
  'luaeval("(function() for _, c in pairs(vim.lsp.get_clients({name=\"asm_lsp\"})) do vim.lsp.stop_client(c.id, true) end vim.cmd(\"edit\") return \"ok\" end)()")'
```

## When extending tooling

Any new language server, linter, or analyzer attached to `.asm` files
must consume the same `assembler = nasm` /
`instruction_set = x86-64` contract. Do not introduce a tool that
demands a second source of truth for syntax or architecture; if a new
tool needs its own config, derive it from `.asm-lsp.toml` rather than
duplicating the values.
