# 33 — spawn-child

Run `/usr/bin/true` in a child process through libproc's
`spawn_wait` composed helper. Exit 42 iff the child ran
cleanly. Builds on [28-fork-child](../28-fork-child/) — 28
introduced raw `fork` and `wait4`; this example goes one
layer up to the composed helper that hides fork/execve/wait4
behind a single call.

## Introduces

- **`libs/proc/util/spawn_wait`.** The first example to
  reach into libproc's `util/` bucket rather than its raw
  syscall wrappers. `spawn_wait(path, argv, envp)` folds
  the entire fork → execve → wait4 sequence into one call
  and returns the child's raw wstatus. Any error along the
  way propagates as a negative errno; the caller never sees
  the intermediate state.
- **Static `argv` / `envp` arrays.** Both are declared in
  `.rodata` as small pointer arrays: `argv = { path, NULL }`
  and `envp = { NULL }`. That is the whole story — no
  dynamic argument construction. Any real caller that wants
  to pass more arguments extends the `argv` array with more
  pointers before the NUL sentinel.
- **`/usr/bin/true` as the portable no-op binary.** macOS's
  bare `/bin` has no `true` command (`true` on Darwin lives
  at `/usr/bin/true`); modern Linux under usrmerge has
  `/bin` symlinking to `/usr/bin`. `/usr/bin/true` works on
  both — the same portability find the libproc smoke test
  made.

## `wstatus == 0` semantics

`wait4` writes the child's exit status into a raw 32-bit
`wstatus` word using the standard POSIX bit layout. A child
that calls `_exit(N)` produces `wstatus = N << 8`, so
`_exit(0)` produces `wstatus = 0`. `spawn_wait` returns that
`wstatus` value directly; the `test rax, rax / jnz .fail`
check treats any non-zero result as failure — either the
child exited with a non-zero code, was killed by a signal,
or `spawn_wait` itself returned `-errno` because fork or
wait4 broke.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`. Local `/usr/bin/true` runs, the
kernel reports its clean exit through `wait4`,
`spawn_wait` returns 0, and this program's own exit is
42.

## Next

- Back to [examples/README.md](../README.md).
