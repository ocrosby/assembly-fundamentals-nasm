# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The repository is unversioned — only the tip of `main` is maintained
— so entries are grouped by month rather than by version tag.

## Unreleased

- Add `examples/22-struct-return/` — return a 32-byte
  `struct rect { x, y, w, h }` by value. Because the return type
  is too big for the register-pair convention that 18-divmod
  uses, the ABI silently switches to a "return by hidden pointer"
  convention: the caller reserves 32 bytes on the stack, passes a
  pointer to that space as a hidden first arg in `rdi`, and the
  callee writes each field through it. Every programmer-visible
  arg (x, y, w, h) shifts one register to the right (rsi, rdx,
  rcx, r8). The callee returns the same pointer unchanged in
  `rax`. `make_rect(10, 20, 30, 40)` — the caller sums the four
  fields back and exits with 100. Renames the previous
  `22-macros` to `23-macros`. Docs (`17-macros.md` Runnable
  pointer, `14-procedures.md` gains a seventh Runnable entry),
  CI expected-exit table, and the issue-template dropdown are
  all updated to match.

- Add `examples/21-cli-args/` — read command-line arguments.
  The runtime hands `argc` to `rdi` and `argv` to `rsi` per the
  standard C `main(int, char**)` signature; the example prints
  `argv[0]` (the program's own path) via `sys_write` and returns
  `argc` as the exit status. Introduces `argv` as a pointer to an
  array of `char *` pointers indexed at `[rsi + i * 8]`, one
  `mov rsi, [rsi]` dereference to reach the first string, and
  stashing state in `r10` (caller-saved, untouched by `syscall`)
  to survive across two write syscalls without pushing anything.
  Reuses 20-shared-lib's per-platform link recipe — macOS keeps
  `ld -lSystem`; Linux uses `gcc` as the driver so `crt0` unpacks
  the kernel-supplied stack layout into argument registers before
  calling us. Renames the previous `21-macros` to `22-macros`.
  Docs (`17-macros.md` Runnable pointer, `14-procedures.md` gains
  a sixth Runnable entry), CI expected-exit table, and the
  issue-template dropdown are all updated to match.

- Add `examples/20-shared-lib/` — call `puts` from the C library.
  Introduces `extern` for imported symbols, macOS's leading-
  underscore symbol mangling (`_puts` in the Mach-O symbol table),
  entering through `main`/`_main` (not `_start`) so the runtime
  can call `exit()` with the return value, and the `sub rsp, 8`
  pre-alignment that keeps `rsp` 16-byte-aligned at the moment of
  `call`. Includes a per-platform link recipe: macOS keeps `ld
  -lSystem`; Linux switches to `gcc` as the driver so `crt0`
  initializes `libc` before `puts` runs. Renames the previous
  `20-macros` to `21-macros`. Docs (`17-macros.md` Runnable
  pointer, `18-linking.md` gets a new Runnable section pointing at
  this example), CI expected-exit table and Linux install step
  (adds `gcc libc6-dev`), and the issue-template dropdown are all
  updated to match.

- Add `examples/19-struct-ptr/` — pass a `struct point` to a
  subroutine by pointer. `translate(&pt, 3, 4)` mutates both
  fields in place; the caller reads them back and exits with
  `pt.x + pt.y = 37`. Introduces structs as contiguous memory
  addressed via `equ` field-offset constants, passing by pointer,
  mutation-through-pointer, and the `add [mem], reg` RMW form
  that reads, modifies, and writes in one instruction. Renames
  the previous `19-macros` to `20-macros`. Docs (`17-macros.md`
  Runnable, `14-procedures.md` gains a fifth Runnable entry,
  `07-addressing-modes.md` gets its first Runnable section
  pointing at this example), CI expected-exit table, and the
  issue-template dropdown are all updated to match.

- Add `examples/18-divmod/` — a subroutine that returns **two**
  values at once. `divmod(17, 5)` puts the quotient in `rax` and
  the remainder in `rdx` using the ABI's two return-value slots,
  then the caller combines them into a 32 exit status. Introduces
  the fact that the System V AMD64 ABI reserves both `rax` and
  `rdx` for returns, and the natural pairing with the `div`
  instruction which writes both halves in a single cycle. Renames
  the previous `18-macros` to `19-macros`. `docs/17-macros.md`
  Runnable pointer, `docs/14-procedures.md` (gains a fourth
  Runnable entry alongside 14-square, 16-factorial, and
  17-stack-args), `docs/09-arithmetic.md` (gains its second
  Runnable pointer, next to 03-add), the CI expected-exit table,
  and the issue-template dropdown are all updated to match.

- Add `examples/17-stack-args/` — pass eight integer args to
  `sum8(a..h)`. Introduces the six-register cap of the System V
  AMD64 ABI, the right-to-left push order for args 7+, callee-
  side addressing via `[rbp + 16]` / `[rbp + 24]`, and caller
  cleanup with `add rsp, 16`. Renames the previous `17-macros`
  to `18-macros`. `docs/17-macros.md` Runnable pointer, CI
  expected-exit table, and the issue-template dropdown are
  updated to match. `docs/14-procedures.md` gains a third
  Runnable entry alongside 14-square and 16-factorial.

- Add `examples/16-factorial/` — recursion. `factorial(5) = 120`
  computed by a subroutine that calls itself, preserving `n` in
  `rbx` (callee-saved) across the recursive call. Renames the
  previous `16-macros` to `17-macros` to keep the constructive
  sequence intact; `docs/17-macros.md` Runnable pointer, CI
  expected-exit table, and the issue-template dropdown are updated
  to match. `docs/14-procedures.md` gains a second Runnable entry
  pointing at the recursion example alongside the existing 14-square.

- Expand `examples/` into a full I/O curriculum. Old `04-hello`
  removed; eight new examples land at 04–11 covering
  `sys_write`/`sys_read` at char and line granularities, an
  echo-until-EOF loop, and `sys_open`/`sys_close`-based file
  read / write / copy. The existing pedagogy (loops, memory,
  procedures, stack frames, macros) is preserved; those examples
  are renumbered from 05–09 to 12–16.
    * New: `04-write-char`, `05-read-char`, `06-read-line`,
      `07-write-line`, `08-echo-loop`, `09-read-file`,
      `10-write-file`, `11-copy-file`.
    * Renumbered: 05-countdown → 12, 06-sum-array → 13,
      07-square → 14, 08-stack-frame → 15, 09-macros → 16.
    * Every reference across `docs/`, both walkthrough chapters
      (`docs/23`, `docs/24`), the issue-template dropdown, and the
      CI expected-exit table updated to match the new numbering.
    * CI seeds `/tmp/nasm-read-file.txt` and `/tmp/nasm-copy-src.txt`
      before the loop, and pipes empty stdin into the three stdin-
      reading examples so they hit EOF and exit cleanly.

## 2026-07 — Audit follow-up, CI hardening, community files

### Added

- `SECURITY.md` — scope statement, private-report path (GitHub
  Security tab + email fallback), unversioned support statement.
  Also unlocks the "Security policy" badge on the repo landing
  page. (#26)
- `.github/PULL_REQUEST_TEMPLATE.md` — the Summary + Test plan
  shape every recent PR body has used, now templated so a new
  contributor does not have to notice the pattern to match it. (#26)
- `.github/ISSUE_TEMPLATE/`: `config.yml` (disables blank issues,
  points at CONTRIBUTING and SECURITY), `doc-bug.yml`, and
  `example-bug.yml` — required-field forms that mirror the exact
  info the "Reporting bugs" section of CONTRIBUTING already asks
  for. (#26)
- `.github/dependabot.yml` — weekly `github-actions` ecosystem PRs
  so the SHA pins stay current. (#25)
- `CHANGELOG.md` — Keep-a-Changelog-formatted history file, seeded
  with the June 2026 section, plus a `## Changelog` pointer in
  the README. (#27)
- CI: `macos-latest` matrix leg on `examples-build`, so the Mach-O
  + libSystem link path gets exercised the same way a reader
  actually uses it (macOS is the primary target). (#25, #30)

### Changed

- Every GitHub Action in `.github/workflows/ci.yml` is now pinned
  to a full 40-char commit SHA with a `# vX.Y.Z` trailing comment.
  This is the concrete mitigation for the OWASP A03 supply-chain
  signal. (#25)
- `actions/cache` bumped 4.3.0 → 6.1.0 via Dependabot. (#28)
- `actions/checkout` bumped 4.3.1 → 7.0.0 via Dependabot. (#29)
- Stale count references in `README.md` and `docs/README.md`
  updated from "seven runnable programs" to "nine", with the
  chapter-pairing list expanded to 2, 9, 13, 14, 15, and 17. (#24)

### Fixed

- Switch CI matrix from `macos-13` (Intel image, retired by GitHub
  in early 2026) to `macos-latest` — jobs were queuing forever
  waiting on a runner label whose pool had been decommissioned. (#30)

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
