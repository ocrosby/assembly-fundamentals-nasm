# Contributing to assembly-fundamentals-nasm

Thank you for your interest in improving this NASM study companion. This guide
explains how to propose changes, what the project values, and the conventions
every contribution should follow.

## Scope

This repository is a documentation-first study companion for x86-64 assembly
with NASM. Contributions fall into four categories:

- **Corrections** — fix a wrong instruction, broken link, typo, or platform note.
- **Clarifications** — make an existing explanation easier to follow.
- **New topic guides** — add a chapter under [docs/](docs/).
- **Runnable examples** — add a worked program under `examples/` (added as the project grows).

Contributions that expand surface area without serving the study goal (CI
tooling, dependency upgrades, repo cosmetics) are usually deferred. Open an
issue first if you are unsure.

## Before you start

1. **Open an issue** describing the change for anything more than a typo.
   Aligning on shape early avoids wasted work.
2. **Read [CLAUDE.md](CLAUDE.md)** — it captures the audience, voice,
   terminology, and structural conventions every contribution must follow.
3. **Read [docs/README.md](docs/README.md)** — check that the topic you want to
   add does not already exist. Extend before duplicating.

## Repository layout

- `README.md` — public-facing overview.
- `CONTRIBUTING.md` — this file.
- `CLAUDE.md` — project guide: audience, voice, terminology, file shape.
- `docs/` — numbered single-screen topic guides plus an appendix.
- `examples/` — runnable `.asm` programs referenced by the docs (added as
  needed).
- `LICENSE` — MIT.

## Documentation conventions

Summarized here; the authoritative source is [CLAUDE.md](CLAUDE.md).

- **One screen per topic.** Each `docs/NN-*.md` must fit on a single laptop
  screen — roughly 80 source lines including code. Split rather than shrink.
- **Required topic shape.** H1 title, one- or two-sentence motivation, H2
  sections as needed, trailing `## Next` link. Appendix files (cheat sheet,
  references) may end with `## See also` linking back to the index.
- **Platform pairing.** Where macOS and Linux differ, show both under
  explicit `## macOS` / `## Linux` subheadings — **macOS first**, per
  the [platform-priority rule](.claude/rules/platform-priority.md).
- **Terminology.** Use the canonical spellings in CLAUDE.md (x86-64, NASM,
  RFLAGS, System V AMD64 ABI, syscall).
- **Code blocks.** ` ```nasm ` for assembly, ` ```bash ` for shell, ` ```text `
  for debugger or program output. Every block must assemble and run as shown.
- **Voice.** Plain, direct, second-person. No first person in normative prose.
  No emoji.
- **Links.** Use Markdown links; never bare URLs in prose. Link text must
  describe the destination.

## Adding a new topic guide

1. Confirm the topic is not already covered in `docs/`.
2. Decide where it belongs in the reading order. Stable numbers reduce churn —
   prefer appending over renumbering when possible.
3. Create `docs/NN-slug.md` following the required shape.
4. Update [docs/README.md](docs/README.md) so the new topic appears in the
   index.
5. If the new file is inserted into the middle of the sequence, update the
   previous chapter's `## Next` link to point at it.

## Adding a runnable example

1. Place the source under `examples/<topic>/<name>.asm`.
2. Add a sibling `README.md` showing the exact assemble/link/run commands for
   macOS and Linux.
3. Link to it from the relevant `docs/NN-*.md`.
4. Keep examples short and split rather than grow.

## Style notes for NASM source

- Use Intel syntax (NASM default).
- Lowercase mnemonics and register names.
- Local labels (`.next`) for in-procedure jumps; global labels for entry points.
- Define constants with `equ` (assemble-time) or `%define` (textual) — see
  [docs/17-macros.md](docs/17-macros.md).
- Comments explain *why* a value matters at this point, not *what* the
  instruction does.
- Default to RIP-relative addressing: `default rel` at the top of the file.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): summary`.

| Type    | When to use                                                |
|---------|------------------------------------------------------------|
| `docs`  | Anything under `docs/`, the root README, or this file      |
| `feat`  | A new runnable example or new repo capability              |
| `fix`   | Correction to wrong content or broken code                 |
| `chore` | LICENSE, `.gitignore`, repo housekeeping                   |

Examples:

```text
docs(nasm): add stack-alignment chapter
docs(nasm): fix syscall number for macOS write
feat(examples): add memcpy via rep movsb
fix(docs): correct register clobber list in procedures chapter
```

**One concern per commit.** If your description contains "and", split the work.

## Branching and pull requests

- Branch from the latest `main`:
  ```bash
  git fetch origin && git switch -c <type>/<short-slug> origin/main
  ```
- The branch prefix matches the commit type: `feature/`, `hotfix/`, etc.
- Open one PR per logical change. Mixed concerns will be asked to split.
- The PR description should make the rationale obvious to a reader who has not
  seen the issue. Link the issue if one exists.

## Local checks

There is no build system. Optional checks before opening a PR:

```bash
npx markdownlint-cli '**/*.md'
npx cspell '**/*.md'
```

If you add `.asm` examples, assemble and run them on the platform you are
targeting before submitting.

## Editor tooling

The repository ships an `.asm-lsp.toml` that pins
[asm-lsp](https://github.com/bergercookie/asm-lsp) to NASM Intel syntax for
x86-64. If your editor's LSP reports errors like *"unrecognized instruction
mnemonic"* on `default`, `global`, `section`, or `syscall`, or *"unexpected
token at start of statement"* on lines beginning with `%define` or `%ifdef`,
the LSP is running in its default GAS / AT&T / arm64 mode and has not picked
up the config. Restart the LSP client after the first open, or open a known
file like `examples/01-exit-zero/exit-zero.asm` first so asm-lsp loads the
project root.

Do not change source files to silence a misconfigured tool. The `.asm` files
are in NASM Intel syntax by design; phantom diagnostics are always a
tooling problem, never a source problem.

## Reporting documentation bugs

Open an issue with:

- The file path and line range.
- What you read.
- What you expected, with a source if available (the NASM manual, Intel SDM,
  Linux man pages, the System V AMD64 ABI specification).

## Conduct

Be kind, be specific, assume good faith. Disagreement is fine; rudeness is not.

## License

By contributing, you agree that your contribution will be licensed under the
[MIT License](LICENSE).
