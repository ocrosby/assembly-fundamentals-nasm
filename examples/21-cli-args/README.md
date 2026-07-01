# 21 — cli-args

Print `argv[0]` (the program's own name/path) to stdout and return
`argc` as the exit status. Called with no extra args, exits 1.
Called as `./cli-args foo bar`, exits 3 (argc counts the program
name itself). Builds on
[20-shared-lib](../20-shared-lib/) — same `main`-entry pattern, but
this time we're **reading** what the runtime already handed us
rather than calling out into a shared library.

## Introduces

- **The standard `main` calling convention.** The runtime hands
  us `argc` in `rdi` and `argv` in `rsi` — exactly what a C
  program's `int main(int argc, char **argv)` sees. Written in
  assembly, we read them straight out of those registers.
- **`argv` as a pointer to a pointer.** `argv` is not the string;
  it's a pointer to an **array** of string pointers. To reach
  `argv[0]`'s bytes you need `mov rsi, [rsi]` — one dereference
  turns the array pointer into the first string pointer.
- **Indexing an array of pointers.** `argv[i]` lives at
  `[rsi + i * 8]` because each element is 8 bytes (a 64-bit
  pointer). Same `[base + index * scale]` shape as
  `13-sum-array`, but the elements are pointers, not integers.
- **Preserving state across a `syscall`.** `r10` is caller-saved
  and untouched by the `syscall` instruction, so stashing `argc`
  there means we don't need to push/pop anything to keep it alive
  across two `write` syscalls.

Paired with [docs/14-procedures.md](../../docs/14-procedures.md)
and [docs/07-addressing-modes.md](../../docs/07-addressing-modes.md).

## Build and run

```bash
make
./cli-args               # exit=1, prints the binary's path
./cli-args foo bar       # exit=3, still prints just the binary's path
make clean
```

## Build differences from most examples

Same as [20-shared-lib](../20-shared-lib/): on Linux the Makefile
switches from `ld` to `gcc` because we need `gcc`'s `crt0` to
unpack the kernel-supplied stack layout (`argc` at `[rsp]`, argv
above it) into the System V AMD64 `main(int, char**)` argument
registers before calling us. Building with plain `ld` would jump
into `main` with `argc/argv` still on the stack, and this example
would read garbage from `rdi`. On macOS, `ld -lSystem` already
provides the same service via `libSystem`'s startup code.

## Next

- [22-macros](../22-macros/) — `%macro` hides the syscall
  boilerplate that shows up in every example so far.
