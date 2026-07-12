# libs/sig/

POSIX signal-mask primitives packaged as the static archive
`libsig.a`. Tracks the syscall-backed portion of
[`<signal.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/signal.h.html)
that a caller needs to block, unblock, or query pending
signals — without libc's userspace `sigaction`
implementation in front.

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Version

**v1.0** — scaffolding release: `sigprocmask` and
`sigpending`. Both are direct syscall wrappers with
platform-normalized error returns and internal handling of
Linux's `sigsetsize` 4th (sigprocmask) or 2nd (sigpending)
argument. `sigaction`, `sigsuspend`, and helpers for
manipulating a `sigset_t` are deferred pending the
SA_RESTORER trampoline work — see "Not here yet" below.

## Exported symbols

| Symbol        | Arguments                                    | Returns                              |
| ------------- | -------------------------------------------- | ------------------------------------ |
| `sigprocmask` | `how`, `set*`, `oldset*`                     | 0 or negative errno                  |
| `sigpending`  | `set*`                                       | 0 or negative errno                  |

`sigprocmask` changes the calling thread's signal mask. `how`
is one of `SIG_BLOCK` (add the signals in `set` to the mask),
`SIG_UNBLOCK` (remove them), or `SIG_SETMASK` (replace the
mask with `set`). Passing `set = NULL` degenerates the call
into a "read the current mask" query; passing `oldset = NULL`
skips writing the previous mask back.

`sigpending` fills `*set` with the set of signals that are
pending delivery to the calling thread but have not yet been
handled (usually because they are currently blocked). Useful
in a block / critical-section / unblock pattern to check
whether a signal was raised while it was masked.

Symbols are exported under their plain names on both
platforms.

## Sigset layout and platform differences

The `sigset_t` argument to every syscall in libsig is a
bitmap where bit `(N - 1)` corresponds to signal number `N`
(so `SIGINT = 2` is bit `1`). Two platform details matter
for the buffer size:

- **macOS.** BSD's `sigprocmask` (syscall 48) reads a
  4-byte `sigset_t` — the older 32-bit mask that predates
  real-time signals.
- **Linux.** The `rt_sigprocmask` variant reads an 8-byte
  `sigset_t` (`_NSIG / 8 = 8`) and takes an explicit
  `sigsetsize` argument the wrapper injects as `8`.

`syscall/syscall.inc` exposes the platform value as
`SIGSET_BYTES` (4 or 8). Callers who reserve a single
`resq 1` (8 bytes) on both platforms get a portable buffer —
the extra 4 bytes on macOS are simply ignored by the
kernel. Only signals 33..64 (the Linux real-time range) live
outside the low 4 bytes; the portable signals every consumer
usually cares about (SIGINT, SIGTERM, SIGPIPE, …) all fit in
the low 32 bits.

`SIG_BLOCK / SIG_UNBLOCK / SIG_SETMASK` have different
numeric values on the two platforms (macOS uses `1 / 2 / 3`;
Linux uses `0 / 1 / 2`). `syscall.inc` exports the correct
value for each target — callers always use the symbolic
name.

## Portable signal numbers

`syscall/syscall.inc` exports numbers for signals `1..15`,
which agree across macOS and Linux:

```
SIGHUP=1  SIGINT=2  SIGQUIT=3  SIGILL=4   SIGTRAP=5
SIGABRT=6 SIGFPE=8  SIGKILL=9  SIGSEGV=11 SIGPIPE=13
SIGALRM=14 SIGTERM=15
```

Signals in the 16..31 range diverge (`SIGUSR1 = 30` on macOS
but `10` on Linux, etc.). Callers who need those should
split with `%ifdef MACOS` rather than expect libsig to
normalize.

## Building

### macOS

```bash
make -C libs/sig
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the wrappers into
`libsig.a` with `ar rcs`.

### Linux

```bash
make -C libs/sig
```

On Linux, the same `make` invocation assembles with
`nasm -f elf64` and the wrappers use the `rt_sig*` syscall
numbers with `sigsetsize = 8` injected internally.

## Testing

```bash
make -C libs/sig test
```

The test target builds the archive first, then runs the
harness in [`test/run.sh`](test/run.sh):

- **`sig-smoke`** — sub-check 1 installs a mask containing
  only SIGPIPE; sub-check 2 reads the mask back and confirms
  the SIGPIPE bit is set; sub-check 3 unblocks every signal
  via `SIG_UNBLOCK` with a full-1s set; sub-check 4 confirms
  the SIGPIPE bit is clear; sub-check 5 exercises
  `sigpending` (return-only, since pending state is
  process-dependent); sub-check 6 passes a bogus `how`
  argument and confirms the wrapper propagates a negative
  errno (proves the macOS SYSCALL_NORM path fires).

libasm's `panic` is on the link line because the smoke's
`.fail` path calls into it.

## Linking against `libsig.a` from a consumer

```nasm
%include "sig/syscall/syscall.inc"      ; for SIG_BLOCK etc.

extern sigprocmask

section .bss
new_mask: resq 1                        ; 8 bytes; upper 4 unused on macOS
old_mask: resq 1

section .text
    mov qword [new_mask], 1 << (SIGPIPE - 1)
    mov edi, SIG_BLOCK
    lea rsi, [new_mask]
    lea rdx, [old_mask]
    call sigprocmask
    ; ... critical section that ignores SIGPIPE ...
    mov edi, SIG_SETMASK
    lea rsi, [old_mask]
    xor edx, edx
    call sigprocmask
```

Consumer `Makefile`:

```makefile
LIBSIG := ../../libs/sig/libsig.a

$(BIN): $(OBJ) $(LIBSIG)
	$(LD) $(OBJ) $(LIBSIG) -o $(BIN)
```

## Not here yet

- **`sigaction`.** Installing a signal handler on Linux
  requires the `SA_RESTORER` glibc convention — `sa_flags`
  must include `SA_RESTORER` and `sa_restorer` must point at
  a userspace trampoline that calls `SYS_rt_sigreturn` to
  unwind the signal frame. Without it, the process crashes
  when the handler returns. libsig will grow a proper
  `sigaction` wrapper (plus the trampoline) in a later
  version once the design is settled. macOS has no such
  requirement, so the asymmetry only matters for the Linux
  path — but the wrapper needs to work uniformly.
- **`sigsuspend`.** Blocks until a signal not in the given
  mask is delivered, then returns `-EINTR`. Small syscall,
  but callers usually want `sigaction` first (there is no
  point suspending for signals you have no handler for), so
  the two ship together.
- **`sigemptyset / sigfillset / sigaddset / sigdelset /
  sigismember`.** Pure-computation helpers for building
  `sigset_t` values. These will land in `util/` alongside
  `sigaction` — for v1.0 callers write the bit pattern
  directly (`1 << (SIGPIPE - 1)`), which is fine for the
  usual small-set use case.

## See also

- [`../proc/`](../proc/) — process control (`fork`,
  `execve`, `wait4`, `kill`). `kill` sends signals; libsig
  handles receiving them.
- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `panic`).
