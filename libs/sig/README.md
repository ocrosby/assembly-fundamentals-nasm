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

**v1.4** — `sigsuspend` syscall wrapper. Blocks until a
signal not in `*mask` is delivered; the handler runs and
the wrapper returns `-EINTR`. Callers use it to atomically
unblock a signal and wait for it — the sigprocmask +
wait pattern alone has a race window. The wrapper
normalizes a nasty platform asymmetry internally: macOS
BSD sigsuspend takes the sigset_t **by value** in `edi`;
Linux `rt_sigsuspend` takes a **pointer** in `rdi` plus
`sigsetsize` in `rsi`. Callers pass a pointer either way.
The smoke's sub-check M exercises the full round-trip on
Linux; macOS skips M for the same reason it skips I..L
(custom-handler support required).

**v1.3** — custom-handler support on **Linux**. Ships
`sig_restorer`, the SA_RESTORER trampoline that invokes
`SYS_rt_sigreturn` when a handler returns; without it, the
handler's `ret` pops garbage from the signal frame and the
process crashes. Callers who install a real handler set
`sa_flags |= SA_RESTORER` and `sa_restorer = sig_restorer`.
macOS's equivalent (a userspace `sa_tramp` that calls
Darwin's `SYS_sigreturn(uctx, sigstyle, token)`) requires
reading a per-delivery token out of the signal frame the
kernel constructs; that piece is deferred to a future
version pending xnu-internal research. On macOS, callers
keep v1.2's SIG_DFL / SIG_IGN support.

**v1.2** — `sigaction` wrapper for the SIG_IGN / SIG_DFL
dispositions. Callers can now say "ignore SIGPIPE" without
the sigprocmask block-mask dance
([`38-signal-block`](../../examples/38-signal-block/) uses
the older pattern; consumers who prefer disposition-style
reach for `sigaction`). The struct sigaction layout differs
per platform; `syscall/syscall.inc` exposes SIGACTION_SIZE /
SA_HANDLER_OFF / SA_FLAGS_OFF / SA_MASK_OFF (plus
SA_RESTORER_OFF on Linux and SA_TRAMP_OFF on macOS) so
callers build the struct with symbolic offsets.

**v1.1** — sigset bit-manipulation helpers in `util/`:
`sig_zero`, `sig_add`, `sig_del`, `sig_test`. Pure computation
— no syscalls — using the CPU's `bts` / `btr` / `bt`
instructions which take a bit index into a memory bitmap and
compute the byte-and-bit split automatically. Callers no
longer have to write `1 << (SIGPIPE - 1)` inline; they build
sets by name.

**v1.0** — scaffolding release: `sigprocmask` and
`sigpending`. Both are direct syscall wrappers with
platform-normalized error returns and internal handling of
Linux's `sigsetsize` 4th (sigprocmask) or 2nd (sigpending)
argument. `sigaction`, `sigsuspend`, and helpers for
manipulating a `sigset_t` are deferred pending the
SA_RESTORER trampoline work — see "Not here yet" below.

## Exported symbols

### `syscall/` — direct kernel wrappers

| Symbol        | Arguments                                    | Returns                              |
| ------------- | -------------------------------------------- | ------------------------------------ |
| `sigprocmask` | `how`, `set*`, `oldset*`                     | 0 or negative errno                  |
| `sigpending`  | `set*`                                       | 0 or negative errno                  |
| `sigaction`   | `signum`, `act*`, `oldact*`                  | 0 or negative errno *(v1.2)*         |
| `sigsuspend`  | `mask*`                                      | `-EINTR` after a handler runs; other negative errno on failure *(v1.4)* |

### `util/` — pure-computation sigset helpers *(v1.1)*

| Symbol      | Arguments               | Returns                                                             |
| ----------- | ----------------------- | ------------------------------------------------------------------- |
| `sig_zero`  | `set*`                  | void. Clears every byte of the SIGSET_BYTES-sized buffer.           |
| `sig_add`   | `set*`, `sig`           | void. Sets bit `(sig - 1)`.                                         |
| `sig_del`   | `set*`, `sig`           | void. Clears bit `(sig - 1)`.                                       |
| `sig_test`  | `set*`, `sig`           | `1` if bit `(sig - 1)` is set, `0` otherwise.                       |
| `sig_restorer` *(Linux only, v1.3)* | (kernel-called) | SA_RESTORER trampoline. Callers store its address in `sa_restorer` and OR `SA_RESTORER` into `sa_flags` so the kernel invokes it when a handler returns; the trampoline then calls `SYS_rt_sigreturn` to unwind the signal frame. Never called directly. |

The bit-manipulation helpers use x86-64 `bts` / `btr` / `bt`
with a 64-bit register bit index, so the CPU computes the
byte-and-bit split automatically — no manual divide-and-mod
in the wrapper. Undefined behavior for `sig` outside the
range 1..64 (Linux) or 1..32 (macOS) — matching the C
`sigaddset` contract at optimized settings.

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

- **`sig-smoke`** — sub-checks 1–6 cover the v1.0 syscall
  wrappers (`sigprocmask` block/read/unblock, `sigpending`
  return, bogus-`how` error normalization); 7–D cover the
  v1.1 sigset helpers (`sig_zero` / `sig_add` / `sig_del`
  / `sig_test` plus a helper-built-mask round-trip through
  `sigprocmask`); E–H cover v1.2's sigaction with
  `SIG_IGN` (install, verify via write-to-broken-pipe,
  read back through `oldact`, restore `SIG_DFL`); I–L
  **(Linux only)** cover v1.3's custom handler path
  (install real handler + `SA_RESTORER` + `sig_restorer`,
  trigger via broken pipe, observe the handler ran, restore
  `SIG_DFL`). On macOS I–L are skipped via `%ifndef MACOS`
  until sa_tramp support lands.

libasm's `panic` is on the link line because the smoke's
`.fail` path calls into it. libio joins the link line for
the smoke's `pipe` fixture in E–H (and I–L on Linux).

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

- **Custom signal handlers on macOS.** v1.3 ships
  `sig_restorer` (Linux SA_RESTORER trampoline), so Linux
  callers can install real handler functions. macOS's
  equivalent trampoline (`sa_tramp`) needs to invoke
  Darwin's `SYS_sigreturn(uctx, sigstyle, token)`, where
  `token` is a per-delivery value the kernel stores in the
  signal frame at a layout-dependent offset. Reading that
  offset out of the xnu source is on the road map but not
  in this release. Until it lands, macOS callers stick
  with v1.2's SIG_DFL / SIG_IGN dispositions.
- **`sigfillset`.** Trivial (a full-1s fill of the sigset
  buffer) but only meaningful once real handlers are
  installable via `sigaction` — the existing `sig_zero` +
  `sig_add` composition covers building any subset of
  signals, which is what callers actually need before
  `sigaction` lands.

## See also

- [`../proc/`](../proc/) — process control (`fork`,
  `execve`, `wait4`, `kill`). `kill` sends signals; libsig
  handles receiving them.
- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `panic`).
