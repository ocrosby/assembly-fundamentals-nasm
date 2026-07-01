# Runnable Examples

A constructive sequence of small x86-64 NASM programs. Each example
introduces exactly one new atomic concept on top of the previous one,
so reading from `01` to `16` walks the entire control-and-data
vocabulary needed for the early chapters of [../docs/](../docs/).

## The sequence

| #  | Example                                              | Introduces                                                                | Chapter                                       |
|----|------------------------------------------------------|---------------------------------------------------------------------------|-----------------------------------------------|
| 1  | [01-exit-zero](01-exit-zero/)                        | sections, entry symbols, the `syscall` mechanic                           | — (prerequisite for everything below)         |
| 2  | [02-exit-status](02-exit-status/)                    | loading an immediate with `mov`                                           | —                                             |
| 3  | [03-add](03-add/)                                    | integer arithmetic with `add`                                             | [docs/09](../docs/09-arithmetic.md)           |
| 4  | [04-write-char](04-write-char/)                      | `sys_write` with a 1-byte buffer                                          | [docs/02](../docs/02-hello-world.md)          |
| 5  | [05-read-char](05-read-char/)                        | `sys_read`, `.bss`, checking the return value in `rax`                    | [docs/06](../docs/06-data-types.md)           |
| 6  | [06-read-line](06-read-line/)                        | `sys_read` into an N-byte buffer, echoing exactly what was read           | [docs/16](../docs/16-system-calls.md)         |
| 7  | [07-write-line](07-write-line/)                      | `.rodata`, `lea`, `equ $ - msg` — a fixed-length line in one call         | [docs/02](../docs/02-hello-world.md)          |
| 8  | [08-echo-loop](08-echo-loop/)                        | driving `sys_read` in a loop, detecting EOF (`rax == 0`)                  | [docs/13](../docs/13-loops.md)                |
| 9  | [09-read-file](09-read-file/)                        | `sys_open`/`sys_close`, saving fd in `r12`, `-errno` error path           | [docs/16](../docs/16-system-calls.md)         |
| 10 | [10-write-file](10-write-file/)                      | `O_WRONLY \| O_CREAT \| O_TRUNC`, the mode arg, macOS vs Linux `O_*`    | [docs/16](../docs/16-system-calls.md)         |
| 11 | [11-copy-file](11-copy-file/)                        | two open fds in parallel, layered error cleanup                           | [docs/16](../docs/16-system-calls.md)         |
| 12 | [12-countdown](12-countdown/)                        | local labels, `dec`/`jnz` loop idiom                                      | [docs/13](../docs/13-loops.md)                |
| 13 | [13-sum-array](13-sum-array/)                        | `.data`, indexed addressing, load-base-then-index                         | [docs/13](../docs/13-loops.md)                |
| 14 | [14-square](14-square/)                              | `call`/`ret`, System V AMD64 calling convention                           | [docs/14](../docs/14-procedures.md)           |
| 15 | [15-stack-frame](15-stack-frame/)                    | frame-pointer prologue/epilogue, stack locals via `[rbp - N]`             | [docs/15](../docs/15-stack.md)                |
| 16 | [16-macros](16-macros/)                              | `%macro` for a syscall helper                                             | [docs/17](../docs/17-macros.md)               |

Examples 1 and 2 do not have a dedicated chapter — they are the
smallest possible programs and exist so that every later example can
focus on a single new idea instead of bundling it with syscall
mechanics.

## How to build

Each example directory contains a `Makefile` that auto-detects macOS
versus Linux and runs the right `nasm` and `ld` commands.

```bash
cd examples/01-exit-zero
make            # default target — assemble + link
make build      # assemble only (produces the .o)
make link       # link only (produces the executable)
make run        # build (if needed), execute, print the exit status
make clean      # remove the .o and the executable
```

Build artifacts (`*.o` and the unsuffixed executables) are gitignored.

## Platform notes

- **macOS (Intel).** Native; uses the Xcode Command Line Tools' `ld`.
- **macOS (Apple Silicon).** x86-64 Mach-O binaries run under Rosetta. Install
  with `softwareupdate --install-rosetta` if it is not already present.
- **Linux (x86-64).** Native; nothing extra to install beyond NASM and `binutils`.

## Adding a new example

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full workflow. In short:
identify the next atomic concept, append `examples/NN-slug/` to the
sequence, copy the Makefile from any existing example and change the
`NAME :=` line, and update this index.
