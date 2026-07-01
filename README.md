# assembly-fundamentals-nasm

A hands-on reference for learning x86-64 assembly with the Netwide Assembler (NASM).

![CI](https://github.com/ocrosby/assembly-fundamentals-nasm/actions/workflows/ci.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Assembler: NASM](https://img.shields.io/badge/assembler-NASM-blue.svg)](https://www.nasm.us/)
[![Architecture: x86--64](https://img.shields.io/badge/arch-x86--64-lightgrey.svg)](https://en.wikipedia.org/wiki/X86-64)

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Overview

This repository is a structured set of bite-sized guides and worked examples for
writing, assembling, linking, and debugging x86-64 assembly programs with NASM.
It is intended as a self-study companion: start at the top of [docs/](docs/) and
work down, or jump directly to the topic you need. Each guide is short on
purpose so a single concept fits on one screen.

## Features

- One concept per page — every guide in [docs/](docs/) fits on a single screen.
- End-to-end coverage from `hello world` through macros, the stack, and debugging.
- Copy-pasteable examples assembled and linked from the command line.
- Side-by-side notes for macOS and Linux where the syscall ABI differs.
- Cross-references between topics so related ideas are one click apart.

## Requirements

- A 64-bit x86 host (macOS or Linux; Windows via WSL2).
- [NASM](https://www.nasm.us/) `>= 2.15` — see the
  [NASM Manual](https://www.nasm.us/doc/) for syntax and directives.
- A linker (`ld` from Xcode Command Line Tools on macOS, `ld` on Linux).
- A debugger — `lldb` on macOS, `gdb` on Linux — for the debugging guide.
- Optional: `make` for any local build scripts you add.

## Installation

Install NASM and a linker for your platform.

```bash
# macOS (Homebrew)
xcode-select --install
brew install nasm

# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y nasm build-essential gdb

# Fedora
sudo dnf install -y nasm binutils gdb
```

Clone this repository:

```bash
git clone https://github.com/ocrosby/assembly-fundamentals-nasm.git
cd assembly-fundamentals-nasm
```

## Usage

Read the docs in order, starting with the index:

- [docs/README.md](docs/README.md) — table of contents for every topic.
- [docs/01-installation.md](docs/01-installation.md) — verify your toolchain.
- [docs/02-hello-world.md](docs/02-hello-world.md) — assemble, link, and run.
- [docs/21-references.md](docs/21-references.md) — external manuals and reference sites.
- [examples/](examples/) — a constructive sequence of seven runnable programs,
  each with a `Makefile` that auto-detects macOS and Linux.

Assemble, link, and run any example from a guide:

```bash
# macOS (Mach-O 64)
nasm -f macho64 hello.asm -o hello.o
ld -macos_version_min 11.0 -lSystem -o hello hello.o \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)"
./hello

# Linux (ELF64)
nasm -f elf64 hello.asm -o hello.o
ld hello.o -o hello
./hello
```

## Configuration

N/A — there is no runtime configuration. Per-example flags are documented inline
in each guide under [docs/](docs/).

## Development

This repository is documentation and example code; there is no build system to
run. To work on it locally:

```bash
# Lint markdown (optional)
npx markdownlint-cli '**/*.md'

# Spell-check (optional)
npx cspell '**/*.md'
```

When adding a new topic, place it under [docs/](docs/), keep it to a single
screen of vertical scroll, and link it from [docs/README.md](docs/README.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the full guide — scope, conventions, the topic-file shape, commit-message
format, and branching workflow. In short: open an issue describing the change
before sending a substantial PR, and keep documentation contributions short,
scannable, and consistent with the existing guides.

## References

- [NASM Manual](https://www.nasm.us/doc/) — the authoritative reference for
  Netwide Assembler syntax, the preprocessor, output formats, and every
  directive used in this repo.
- [docs/21-references.md](docs/21-references.md) — instruction-set references,
  syscall tables, and further reading.

## License

Released under the [MIT License](LICENSE).
