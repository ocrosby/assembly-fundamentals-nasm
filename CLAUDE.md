# CLAUDE.md — assembly-fundamentals-nasm

This repository is a personal study companion for x86-64 assembly with NASM.
Material is captured as short, single-screen guides under [docs/](docs/) and
runnable example programs in `examples/` (added as the project grows).

**Long-term intent:** the docs and examples here may eventually be reorganized
into a book. Treat every file you write as a *candidate book passage* — favor
quality and consistency over speed, and never write something you would not be
willing to print.

---

## Audience & Voice

- **Reader:** a working programmer who has not written assembly before. Comfort
  with C-level concepts (pointers, stack, registers) can be assumed; familiarity
  with x86-64 cannot.
- **Voice:** plain, direct, second-person ("you assemble it with…"). Avoid
  marketing tone, avoid "simply", avoid emoji.
- **Tense:** present tense for behavior ("`mov` copies a value"), imperative for
  instructions ("Assemble the file with…").
- **Mood:** patient, not breezy. The reader is learning; do not skip steps for
  the sake of looking concise.

When in doubt, write as if the paragraph might be lifted into a print book a
year from now.

---

## Project Layout

- `README.md` — public-facing repo overview. Follows the standard in
  `~/.claude/rules/readme-standard.md`.
- `docs/` — numbered, single-screen topic guides.
  - `docs/README.md` is the index.
  - Filename pattern: `NN-slug.md` where `NN` controls reading order.
- `examples/` — runnable `.asm` programs referenced by the guides (add when a
  guide grows past the single-screen budget).
- `LICENSE` — MIT.
- `.asm-lsp.toml` — language-server config (see **Editor Tooling** below).
  Do not delete it.

---

## Editor Tooling

Every `.asm` file in this repo is **NASM Intel syntax targeting x86-64**.
That contract is enforced for editors by `.asm-lsp.toml` at the repo root,
which pins asm-lsp to `assembler = "nasm"` and
`instruction_set = "x86-64"`. Without this file asm-lsp defaults to GAS /
AT&T syntax (and on Apple Silicon also defaults to `arm64`), and every
NASM preprocessor directive, every NASM assembler directive, and every
Intel-syntax operand is flagged as a phantom error.

### When LSP diagnostics look wrong

If `asm-lsp` reports any of these on freshly-written, otherwise-valid
NASM, the **tool is misconfigured**, not the source:

- "unexpected token at start of statement" on lines starting with
  `%define`, `%ifdef`, `%else`, `%endif`, `%macro`, `%endmacro`.
- "unrecognized instruction mnemonic" on `default`, `global`, `section`,
  `extern`, `equ`, or even on real instructions like `syscall`.
- "invalid operand for instruction" on plain Intel-syntax operands such
  as `mov rdi, 42` or `lea rsi, [msg]`.

The fix is **always** in `.asm-lsp.toml`. Do not change the source files
to match a misconfigured tool: do not switch to AT&T syntax, do not add
per-file pragmas, do not insert inline disables, do not delete the
`%ifdef MACOS` blocks. The source is correct by design.

### Verifying the config is loaded

When running inside Neovim, query the live LSP for the open buffer:

```bash
nvim --server "$NVIM" --remote-expr \
  'luaeval("vim.json.encode(vim.diagnostic.get(vim.fn.bufnr(_A)))", "examples/01-exit-zero/exit-zero.asm")'
```

Zero diagnostics on a known-good example means the config is loaded. If
you change `.asm-lsp.toml`, restart the LSP client:

```bash
nvim --server "$NVIM" --remote-expr \
  'luaeval("(function() for _, c in pairs(vim.lsp.get_clients({name=\"asm_lsp\"})) do vim.lsp.stop_client(c.id, true) end vim.cmd(\"edit\") return \"ok\" end)()")'
```

### When extending tooling

Any new language server, linter, or analyzer attached to `.asm` files
must consume the same `assembler = nasm` / `instruction_set = x86-64`
contract. Do not introduce a tool that demands a second source of truth
for syntax or architecture; if a tool needs its own config, derive it
from `.asm-lsp.toml` rather than duplicating the values.

---

## Documentation Rules

These rules are specific to this repo. They sit on top of (and never contradict)
the global documentation principles in `~/.claude/rules/docs-principles.md`.

### One screen per topic

Each `docs/NN-*.md` file must fit comfortably on a single laptop screen — read
as roughly **80 source lines** including code. If a topic outgrows that budget:

1. Split it into `NN-topic-a.md` and `NN-topic-b.md` (or similar), keeping the
   sequence numbers contiguous.
2. Cross-link them at the bottom of each file under `## Next` / `## See also`.

Do not solve overflow by shrinking font, deleting examples, or removing the
"Next" link — those are the parts that make the guide usable.

### Required shape of a topic file

```markdown
# Topic Title

One- or two-sentence motivation.

## H2 sections as needed

Body, examples, tables.

## Next

- [Next Topic](NN-next.md)
```

The trailing `## Next` link is mandatory on every numbered topic file in the
main reading sequence. Appendix-style files (cheat sheet, references) may end
with a `## See also` link back to the index instead. Sequence is the navigation.

### Code blocks

- Use ` ```nasm ` for NASM source.
- Use ` ```bash ` for shell.
- Use ` ```text ` for debugger output or program output.
- Every code block must assemble and run as shown, on the platform it claims to
  target. Do not paste pseudo-assembly.

### Platform conventions

- Default target is **x86-64, Intel syntax, NASM**.
- Where Linux and macOS differ (syscall numbers, linking, entry symbol), give
  both, side-by-side, under explicit `## Linux` / `## macOS` subheadings.
- Do not silently prefer one platform — this repo is read on both.

### Terminology

Use these spellings consistently across all docs:

| Use this              | Not this                          |
|-----------------------|-----------------------------------|
| x86-64                | x64, amd64, X86_64                |
| NASM                  | nasm (in prose)                   |
| RFLAGS                | EFLAGS (when discussing 64-bit)   |
| System V AMD64 ABI    | SysV calling convention, SVR4 ABI |
| syscall (noun + verb) | sys-call, system-call             |

### Linking and cross-references

- Use Markdown links, never bare URLs in prose ("see [Procedures](14-procedures.md)").
- Link forward and backward between adjacent chapters; readers must be able to
  navigate without going back to the index.

---

## When Adding a New Topic

1. Decide where it belongs in the reading order. Renumber later files only if
   strictly necessary — stable numbers reduce churn.
2. Add the file under `docs/NN-slug.md`.
3. Update `docs/README.md` so the new topic appears in the index.
4. If the topic supersedes or expands an existing one, update the older file's
   `## Next` link and add a `## See also` pointing back.

---

## When Adding a Runnable Example

1. Place the source under `examples/<topic>/<name>.asm`.
2. Add a sibling `README.md` showing the exact assemble/link/run commands for
   Linux and macOS.
3. Link to it from the relevant `docs/NN-*.md` file.
4. Keep examples short enough to read at a glance — split, don't grow.

---

## Book-Track Discipline

Because this material may become a book:

- **Self-contained chapters.** A reader should be able to drop into any
  `docs/NN-*.md` and follow it. Forward references are fine; assumed prior
  knowledge from earlier chapters should be brief and re-introduced in context.
- **No dead ends.** Every chapter ends with a forward link.
- **No "I" or "we" in normative explanations.** Personal asides belong in
  commit messages, not in the docs.
- **Avoid version-bound advice** ("as of NASM 2.16…") unless the version
  actually matters. Date-stamped prose ages poorly in print.
- **Reuse vocabulary** — once a term is introduced (e.g., "callee-saved"), use
  it the same way everywhere.

---

## Commit Discipline

Follow Conventional Commits (see `~/.claude/CLAUDE.md`):

- `docs(nasm): add stack alignment chapter`
- `docs(nasm): fix syscall number for macOS write`
- `chore: gitignore object files`

One concern per commit. Never mix a new chapter with a renumbering pass.

---

## What NOT to Do

- Do not introduce a build system (Makefile, CMake) until at least three
  examples share enough boilerplate to justify it. This repo is documentation
  first.
- Do not add a `FAQ.md` — fold questions into the relevant chapter (see
  `~/.claude/rules/docs-principles.md`).
- Do not write speculative chapters about topics not yet covered by an example
  you have actually run.
- Do not let any single `docs/*.md` file grow past one screen without splitting
  it.
