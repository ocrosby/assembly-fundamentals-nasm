# libs/proc/

Process-control primitives packaged as the static archive
`libproc.a`. Tracks the syscall-backed portion of POSIX
[`<unistd.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/unistd.h.html),
[`<sys/wait.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/sys_wait.h.html),
and [`<signal.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/signal.h.html)
— specifically the primitives needed to fork, wait for, identify,
and signal processes from raw assembly.

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Version

**v1.0** — `fork`, `wait4`, `getpid`, `getppid`, `kill`. Enough
to spawn a child, wait for it to exit, decode the exit status,
and check whether a pid is still alive. `execve` is
deliberately excluded; see "Not here yet".

## Exported symbols

| Symbol     | Arguments                                                            | Returns                                                                   |
| ---------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `fork`     | (none)                                                               | Parent: child pid. Child: 0. Failure: -errno.                             |
| `wait4`    | `pid` (int), `wstatus*` (int*), `options` (int), `rusage*` (void*)   | Reaped pid, 0 (with `WNOHANG`), or -errno.                                |
| `getpid`   | (none)                                                               | Calling process's pid. Never fails.                                       |
| `getppid`  | (none)                                                               | Calling process's parent pid. Never fails.                                |
| `kill`     | `pid` (int), `sig` (int)                                             | 0 or -errno. `sig=0` is the canonical existence-and-permission probe.     |

## `fork` semantics

The wrapper returns the POSIX-shaped result on both platforms:

- **Parent**, on success: `rax = child's pid` (positive int).
- **Child**, on success:  `rax = 0`.
- On failure: `rax = -errno` in the original process.

XNU's raw `SYS_fork` (2) does not return 0 in the child on its
own — the kernel returns the child's pid in `rax` and sets
`rdx = 1` as a "you are the child" flag. libproc's `fork.asm`
reads that flag and zeroes `rax` in the child, so callers see
the same convention on both platforms.

## `wait4` status decoding

`wstatus` is a raw status word. Decode with the standard bit
patterns; they match on macOS and Linux:

```
WIFEXITED(x)   = ((x) & 0x7f) == 0
WEXITSTATUS(x) = ((x) >> 8) & 0xff
WIFSIGNALED(x) = (((x) & 0x7f) + 1) >> 1 > 0
WTERMSIG(x)    = (x) & 0x7f
WIFSTOPPED(x)  = ((x) & 0xff) == 0x7f
WSTOPSIG(x)    = ((x) >> 8) & 0xff
```

A child that calls `_exit(42)` produces `wstatus = 42 << 8 =
0x2a00`. A child terminated by `SIGKILL` (signal 9) produces
`wstatus = 9` (low seven bits).

## Not here yet

- **`execve(path, argv, envp)`.** Straightforward at the
  syscall level — SYS_execve = 59 on both platforms — but
  building an `argv` array of `char *` pointers from raw
  assembly is a nontrivial exercise and, more importantly,
  the failure modes of a child that couldn't `exec` (fork
  succeeded but the target binary is missing, wrong arch,
  or a symlink loop) deserve a considered smoke test.
  Reserved for v1.1.
- **`waitid`.** A superset of `wait4` with a `siginfo_t`
  output shape and finer-grained state selectors
  (WEXITED / WSTOPPED / WCONTINUED as bitflags). Provides
  no new capability at this precision; `wait4` covers the
  common case.
- **`sigaction` / `sigprocmask`.** Signal handling is a large
  design surface (per-signal disposition, alternate stacks,
  restart semantics, SA_SIGINFO handler ABIs) that would
  drag the archive far past "process control" into a
  parallel `libsignal`. Deferred.
- **`setpriority` / `getpriority` / `nice`.** Fine grained
  scheduling knobs. Callers who need them can add a wrapper
  in a v1.1; they are one-syscall shims with no per-platform
  surprises.

## Building

```bash
make -C libs/proc
```

Produces `libs/proc/libproc.a`.

## Testing

```bash
make -C libs/proc test
```

The test target builds the archive first, then runs the harness
in [`test/run.sh`](test/run.sh):

- **`proc-smoke`** — nine sub-checks covering all five
  wrappers: getpid/getppid sanity, fork, child `_exit(42)`,
  parent `wait4` returning the child pid with the expected
  `wstatus`, and `kill(reaped_pid, 0)` returning `-ESRCH`.
- **`c-smoke`** — links `libproc.a` from a C toolchain and
  exercises every exported symbol with `__asm__` labels
  pinning the reference to libproc's bare names (bypassing
  Mach-O's `_fork` / `_wait4` / etc mangling that would
  otherwise fall back to libc).

Both must print `PASS` for the target to exit 0.

## See also

- [`../asm/`](../asm/) — formatting helpers (`print_int`,
  `print_string`) useful when a parent process wants to
  report on its children.
- [`../time/`](../time/) — `getrusage` reports CPU-time
  accounting for the current process or its waited-on
  children; the same `struct rusage` layout is documented
  there.
