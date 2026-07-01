# Project Rules

This directory holds atomic, named rules that govern work in this repo.
Each file describes one policy: what it is, why it exists, and how to
recognize when it is being violated.

These rules are project policy — read them before changing files that
fall under their scope. `CLAUDE.md` at the repository root indexes
them.

## Current rules

- [asm-lsp-config.md](asm-lsp-config.md) — `.asm` files are NASM Intel
  syntax for x86-64; `.asm-lsp.toml` enforces this for editors; do not
  change source to silence misconfigured tooling.
- [asm-style.md](asm-style.md) — NASM source uses 4-space indent,
  labels on their own line, and instructive inline comments that
  explain intent rather than restating the opcode.
- [platform-priority.md](platform-priority.md) — macOS is the
  primary target; docs lead with the macOS path, examples verify on
  macOS first, Linux is a supported secondary target.
- [nasm-correctness.md](nasm-correctness.md) — the four semantic
  invariants the NASM Manual mandates for x86-64 sources:
  case-sensitivity, square brackets for memory, size hints, and
  `default rel`.

## Adding a rule

1. Create `<topic>.md` in this directory with the frontmatter shape
   used by the existing rules (`name`, `description`, `type`).
2. Add a one-line entry to the **Current rules** list above.
3. Add a matching one-line pointer to the **Project Rules** section of
   `../../CLAUDE.md`.
4. Keep the rule body focused on one policy. If you find yourself
   writing "additionally…" or "also…", split into a second file.
