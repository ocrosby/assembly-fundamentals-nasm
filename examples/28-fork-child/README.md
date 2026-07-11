# 28 — fork-child

Fork a child that immediately exits with status 42, wait for
it in the parent via `wait4()`, and re-exit with the child's
status decoded from the `wstatus` word. Builds on
[27-listen-socket](../27-listen-socket/) by adding one new
atomic concept: linking against `libs/proc/libproc.a` and
calling `fork()`.

## Introduces

- **`libs/proc/libproc.a` as a link target.** Same mechanic
  as 25-open-socket introducing `libsock.a`: change the
  `LIB :=` line in the Makefile, declare `extern fork, wait4`
  in the source, and the linker resolves the calls against
  the new archive at link time. Every later example that
  needs process control — spawning a client subprocess to
  drive a socket listener, running a helper binary, waiting
  for CPU-bound work to finish — depends on this base.
- **`fork(2)`.** The primitive that splits one running
  process into two nearly-identical ones. The parent
  receives the child's pid; the child receives 0. libproc's
  `fork.asm` normalizes Darwin's raw `rdx = 1` "you are the
  child" convention to POSIX's `rax = 0` in the child, so
  the `test rax; jz .child` branch works uniformly on both
  platforms.
- **`wait4(2)` and `wstatus` decoding.** The parent calls
  `wait4(pid, &wstatus, 0, NULL)` to block until the child
  exits, then extracts the exit code with
  `WEXITSTATUS(x) = (x >> 8) & 0xff`. That is the whole
  `shr eax, 8 / and eax, 0xff` sequence at the end of the
  parent branch.

## Why exit 42?

`_exit(42)` in the child feeds through `wait4` into
`wstatus = 42 << 8 = 0x2a00`. The parent extracts the low
byte after shifting right by 8, which gives 42, then re-exits
with the same value. The CI expected-exit map asserts the
final process exit is 42, so the whole fork/wait/decode cycle
is verified end-to-end. Any mistake in the fork branch, the
wait4 wiring, or the wstatus decode would produce a
different exit code and fail CI.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`. As with any test involving fork, the
program produces no output on the success path — success is
signalled by the exit code.

## Next

- Back to [examples/README.md](../README.md).
