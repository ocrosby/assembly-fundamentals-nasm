# Signals

A signal is an asynchronous notification the kernel delivers
to a process — SIGINT when the user hits Ctrl-C, SIGPIPE when
a write hits a closed reader, SIGSEGV when the CPU faults on
a bad memory access. Every process has three levers for each
signal: the mask (block delivery), the pending set (which
blocked signals have queued up), and the disposition
(default, ignore, or a handler function). This repo's
[`libsig`](../libs/sig/) covers the first two; the third —
handler installation via `sigaction` — is deferred for
reasons explained below.

## Sigset layout

A `sigset_t` is a bitmap where bit `(N - 1)` corresponds to
signal number `N`. `SIGINT` is signal 2, so bit 1; `SIGPIPE`
is signal 13, so bit 12. The buffer size differs per platform:

| Platform | `SIGSET_BYTES` | Rationale                                                        |
| -------- | -------------- | ---------------------------------------------------------------- |
| macOS    | 4              | BSD's original 32-bit mask; no real-time signals.                |
| Linux    | 8              | `rt_sig*` variants use `_NSIG / 8 = 8` bytes.                    |

Reserving 8 bytes on both platforms (`resq 1`) is portable —
the kernel on macOS ignores the upper 4. Every signal number
in the low-16 range (SIGHUP through SIGTERM) fits in bit
positions 0..15.

## The three mask operations

`sigprocmask(how, set, oldset)` mutates the calling thread's
signal mask. `how` picks the operation:

- **SIG_BLOCK** — union the mask with `set`. Signals in
  `set` are added to what is already blocked.
- **SIG_UNBLOCK** — subtract `set` from the mask.
- **SIG_SETMASK** — replace the mask with `set` outright.

Numeric values for `SIG_*` differ (macOS uses `1/2/3`, Linux
uses `0/1/2`), so callers use the symbolic name and let
`libsig` resolve the difference.

## Blocked signals go to `sigpending`

When a signal is raised while blocked, the kernel does not
discard it — it queues it and delivers when the mask is
lifted. `sigpending(set)` fills `*set` with the signals
currently queued for this thread. This turns "block a
signal" into "block and know whether it was raised", which
is what makes SIG_BLOCK useful for critical sections rather
than just a mute.

The [`38-signal-block`](../examples/38-signal-block/) example
walks the full pattern end to end: block SIGPIPE, write to
a broken pipe, verify via `sigpending` + `sig_test` that the
signal was queued, exit before unblocking.

## Why `sigaction` is not here yet

Installing a signal handler on Linux requires the
`SA_RESTORER` glibc convention. `sa_flags` must include
`SA_RESTORER` and `sa_restorer` must point at a userspace
trampoline that calls `SYS_rt_sigreturn` to unwind the
signal frame. Without it, the process crashes when the
handler returns. macOS has no such requirement — its kernel
finds the return trampoline on its own — but the wrapper
needs to work uniformly. libsig will grow a proper
`sigaction` wrapper (plus the trampoline) in a later
version once the design is settled.

Until then, callers who need "ignore this signal" reach for
the block-mask pattern via `sigprocmask` (per-signal, thread
local, no trampoline required) or the per-call
`MSG_NOSIGNAL` / `SO_NOSIGPIPE` socket flags.

## See also

- [`libs/sig/`](../libs/sig/) — the archive with all the
  sigprocmask / sigpending wrappers and sigset helpers.
- [`27-libraries.md`](27-libraries.md) — the archive index
  this chapter is a companion to.
- [`examples/38-signal-block/`](../examples/38-signal-block/)
  — the runnable that exercises everything above.

## Next

- Back to [docs/README.md](README.md).
