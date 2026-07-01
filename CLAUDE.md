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
- `examples/` — runnable `.asm` programs organized as a constructive sequence
  (`01-…`, `02-…`, …). See **Runnable Examples** below for the full rules.
- `LICENSE` — MIT.
- `.asm-lsp.toml` — language-server config. See
  [.claude/rules/asm-lsp-config.md](.claude/rules/asm-lsp-config.md).
  Do not delete it.
- `.claude/rules/` — atomic project rules. See **Project Rules** below.

---

## Project Rules

Atomic project rules live as individual files under
[`.claude/rules/`](.claude/rules/). Each file describes one policy:
what it is, why it exists, and how to recognize when it is being
violated. **Read every file under `.claude/rules/` before changing
work in this repo** — these rules are not duplicated in `CLAUDE.md`,
and skipping them will produce changes that miss project policy.

Current rules:

- [asm-lsp-config](.claude/rules/asm-lsp-config.md) — every `.asm`
  file is NASM Intel syntax for x86-64; `.asm-lsp.toml` enforces this
  for editors; phantom LSP errors mean the tool is misconfigured, not
  the source.
- [asm-style](.claude/rules/asm-style.md) — NASM source uses 4-space
  indent (enforced by `.editorconfig`), labels on their own line, and
  instructive inline comments that explain intent rather than
  restating the opcode.
- [platform-priority](.claude/rules/platform-priority.md) — **macOS
  is the primary development target.** Docs lead with the macOS
  path, examples verify on macOS before shipping, Linux is a
  supported secondary target.
- [nasm-correctness](.claude/rules/nasm-correctness.md) — the four
  semantic invariants the [NASM Manual](https://www.nasm.us/doc/)
  mandates for x86-64 sources: case-sensitivity, square brackets
  for every memory reference, size hints when NASM cannot infer,
  and `default rel` in every file. Violations produce wrong code
  or relocation errors, not just ugly diffs.

To add a rule, follow the workflow in
[.claude/rules/README.md](.claude/rules/README.md).

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
- **macOS is the primary target.** See
  [.claude/rules/platform-priority.md](.claude/rules/platform-priority.md)
  for the full policy. In short: new docs lead with the macOS path
  under `## macOS`, then the Linux form under `## Linux`; new examples
  must build and run on macOS before shipping; toolchain and debugger
  defaults favor macOS.
- Where macOS and Linux differ (syscall numbers, linking, entry symbol),
  give both under explicit `## macOS` / `## Linux` subheadings — macOS
  first, Linux second.
- Linux stays fully supported. Do not break the ELF path, and do not
  drop the `%ifdef MACOS` / `%else` branches in cross-platform sources.

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

- Use Markdown links, never bare URLs in prose (e.g., `[Procedures](14-procedures.md)`).
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

## Runnable Examples

Examples live under `examples/` and are organized as a **constructive
sequence**. This is an intentional design decision — do not flatten it back
into topical directories.

### Constructive-sequence rule

- Every example introduces **exactly one new atomic concept** on top of the
  example immediately before it. If your new example would skip a step, add
  the missing prerequisite first.
- Directory names use the form `NN-slug`, where `NN` is the zero-padded
  position in the sequence and `slug` describes the concept being
  introduced (e.g., `01-exit-zero`, `06-sum-array`).
- Renumber later directories only when strictly necessary. Stable numbers
  reduce churn and protect cross-references in the docs.
- Examples 1 and 2 (the smallest possible programs) intentionally have no
  matching chapter — they exist so every later example can focus on a
  single new idea instead of bundling it with syscall mechanics.

### Required files in each `examples/NN-slug/`

- `<slug>.asm` — the source. Cross-platform via a `%ifdef MACOS` block at
  the top; declare both `_start` and `_main` as entry symbols so neither
  linker needs `-e`.
- `Makefile` — see Makefile conventions below.
- `README.md` — what the example introduces, the expected exit code or
  output, build commands (`make`, `make run`, `make clean`), and a link to
  the next example in the sequence.

### Makefile conventions

Every example's `Makefile` must define these phony targets:

| Target  | Behavior                                                    |
|---------|-------------------------------------------------------------|
| `all`   | Default. Assembles and links the binary.                    |
| `build` | Assembles the source to `.o`.                               |
| `link`  | Links the `.o` into the executable.                         |
| `run`   | Runs the binary and prints its exit status.                 |
| `clean` | Removes the `.o` and the executable.                        |

The Makefile auto-detects platform with `uname -s` and selects the correct
`nasm` format (`-f elf64` vs `-f macho64 -DMACOS`) and `ld` invocation
(`ld` vs `ld -macos_version_min 11.0 -lSystem -syslibroot $(xcrun ...)`).
Per-example `README.md` files document `make` / `make run` / `make clean`
only — the raw `nasm` and `ld` commands are not restated.

### When adding a new example

1. Identify the next atomic concept in the sequence.
2. Create `examples/NN-slug/` with the three required files. Copy the
   `Makefile` from any existing example and change the `NAME :=` line.
3. Add a row to the table in `examples/README.md` in sequence order.
4. Add or update a `## Runnable` section in the relevant `docs/NN-*.md`
   chapter to point at the new example.
5. Verify it assembles, links, and runs on both macOS and Linux before
   shipping.

### Build artifacts

`*.o`, `*.dSYM/`, and built example binaries are gitignored. The pattern
in `.gitignore` ignores every file inside `examples/NN-*/` and then
un-ignores `*.asm`, `Makefile`, and `README.md` — so new examples need no
gitignore update.

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
