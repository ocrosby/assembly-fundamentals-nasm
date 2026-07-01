---
name: macOS-first platform priority
description: Development targets macOS first — docs lead with the macOS path, examples verify on macOS before shipping, toolchain and debugger defaults favor macOS. Linux stays fully supported as a secondary target.
type: project
---

# macOS-First Platform Priority

Development in this repo targets **macOS first**. Linux is still fully
supported and must keep working, but when a choice has to be made
about which platform to lead with, macOS wins. This is a deliberate
project decision — do not roll it back to "both platforms are equal"
because a chapter reads more symmetrically that way.

## What this changes

- **Docs.** When platform-specific commands or ABI details differ,
  show the **macOS** form first under a `## macOS` subheading, then
  the **Linux** form under `## Linux`. Do not present the two as
  equal alternatives, do not lead with Linux.
- **Examples.** Every new `.asm` example must be verified with
  `make && make run` on macOS (Intel or Apple Silicon under Rosetta)
  before shipping. Linux verification is encouraged, but macOS is
  the blocking check.
- **Instruction sets and syscalls.** Keep the `%ifdef MACOS` /
  `%else` structure in cross-platform sources. Do **not** invert it
  so Linux becomes the `%ifdef` case; macOS stays as the explicit,
  first-read path.
- **Toolchain and installation notes.** List the macOS install path
  first (Homebrew, Xcode Command Line Tools). Linux (`apt` / `dnf`
  / `pacman`) comes second.
- **Debugging.** Default to `lldb` in examples and prose. `gdb`
  sections are welcome but sit after `lldb`, not before.
- **Linker invocations.** Show the `ld -macos_version_min ... -lSystem
  -syslibroot ...` form first. Show plain `ld` for Linux second.

## What this does NOT change

- Linux remains a supported build target. The Makefiles' `uname -s`
  detection must keep producing a working ELF binary on Linux, and
  new examples must still build there. macOS being the primary
  target does not license Linux breakage.
- Windows via WSL2 continues to count as Linux for platform-pairing
  purposes.
- The `asm-lsp` NASM / x86-64 contract from
  [asm-lsp-config.md](asm-lsp-config.md) is orthogonal to the
  primary-target choice — the syntax dialect does not change.
- The `.editorconfig` and asm-style conventions from
  [asm-style.md](asm-style.md) are not platform-dependent.

## Existing content

Older chapters written before this rule lead with Linux (see
`docs/02-hello-world.md`, `docs/16-system-calls.md`, and the root
`README.md` Installation section). **Do not rewrite them purely to
reorder the platform sections.** The rule applies to new content;
existing content converges over time as chapters are touched for
other reasons.
