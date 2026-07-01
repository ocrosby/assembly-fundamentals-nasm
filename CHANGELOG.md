# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The repository is unversioned — only the tip of `main` is maintained
— so entries are grouped by month rather than by version tag.

## Unreleased

- Placeholder for changes on `main` since the last dated section
  below. Move to a dated section when the batch settles.

## 2026-06 — Initial documentation, examples, and CI

### Added

- Documentation-first repository structure: root `README.md` in the
  standard shape, `CONTRIBUTING.md`, a project `CLAUDE.md`, and an
  MIT `LICENSE`. (#2, #3)
- 20-chapter main-sequence guide under `docs/` covering
  installation, hello world, NASM syntax, registers, sections, data
  types, addressing modes, data movement, arithmetic, bitwise &
  shifts, comparison & flags, jumps, loops, procedures, the stack,
  system calls, macros, linking, debugging, and a cheat sheet. (#2)
- Appendix material under `docs/`: external references, a NASM
  syntax cheat sheet, an `lldb` walkthrough on macOS, and a `gdb`
  walkthrough on Linux. (#2, #16, #17, #18)
- Extended-coverage chapter: `docs/25-floating-point.md` covering
  scalar single/double-precision arithmetic on the SSE unit,
  comparison, int↔float conversion, and the System V AMD64 FP
  calling convention. (#22)
- Constructive `examples/` sequence with per-directory `Makefile`s
  that auto-detect macOS vs Linux — `01-exit-zero`, `02-exit-status`,
  `03-add`, `04-hello`, `05-countdown`, `06-sum-array`,
  `07-square`, `08-stack-frame`, `09-macros`. Every example is
  cross-platform via `%ifdef MACOS` and declares both `_start` and
  `_main` so neither linker needs `-e`. (#5, #20)
- `.claude/rules/` policy files:
  `asm-lsp-config.md` (NASM x86-64 dialect for `asm-lsp`),
  `asm-style.md` (4-space indent, label-on-own-line, instructive
  comments), and `platform-priority.md` (macOS is the primary target;
  docs lead with the macOS path, examples verify on macOS first). (#6, #8, #10)
- `.asm-lsp.toml` and `.editorconfig` to enforce the same
  conventions in editors that read them. (#6, #8)
- CI workflow (`.github/workflows/ci.yml`) with two jobs: markdown
  link check via `lycheeverse/lychee-action`, and an
  `examples-build` job that installs `nasm` and runs every example
  under a hardcoded `(dir → expected-exit)` table. Missing example
  directories are skipped, not failed. `.lycheeignore` filters the
  documented false-positive placeholders. (#21, #23)

### Changed

- Every example source, every NASM code block in `docs/`, and every
  platform-ordering across the tree switched to a uniform style:
  4-space indent, labels on their own line, `## macOS` before
  `## Linux`, `xmm` shortcuts first. This was rolled out
  incrementally over six PRs. (#8, #9, #11, #12, #14, #15)
- Root `README.md` gained a `## References` section with the NASM
  Manual link and a pointer to `docs/21-references.md`. (#7)
- `docs/16-system-calls.md` syscall tables sorted by ascending
  syscall number, and its register-convention table lifted into a
  shared section (it is the System V AMD64 ABI on both platforms,
  not a Linux-only detail). (#13, #11)

### Fixed

- `docs/13-loops.md` `sum_arr`: previously used `[arr + rcx*8]`
  which does not assemble for Mach-O 64-bit; now loads the base
  with `lea rbx, [arr]` before indexing. (#5)
- `docs/20-cheat-sheet.md`: appendix file was missing a trailing
  `## See also`; added. (#19)
- `CLAUDE.md`: illustrative `[Procedures](14-procedures.md)` example
  in prose was parsed as a real link and reported broken; wrapped in
  backticks so it is unambiguously an inline code demonstration. (#19)
- CI `examples-build` job: the `|| true` pattern was clobbering `$?`
  and reporting every non-zero-exit example as `exit=0`. Replaced
  with `got=0; ./bin || got=$?`. (#23)
- CI link check: `wiki.osdev.org` returns 403 to lychee's default
  user agent — added to `.lycheeignore`. (#23)
