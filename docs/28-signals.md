# Signals

A signal is an asynchronous notification the kernel delivers
to a process — SIGINT when the user hits Ctrl-C, SIGPIPE when
a write hits a closed reader, SIGSEGV when the CPU faults on
a bad memory access. Every process has three levers for each
signal: the mask (block delivery), the pending set (which
blocked signals have queued up), and the disposition
(default, ignore, or a handler function). This repo's
[`libsig`](../libs/sig/) covers all three.

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

## Handler installation via `sigaction`

`sigaction(signum, act, oldact)` installs a disposition for
one signal. `act` points at a `struct sigaction` whose
per-platform layout libsig exposes as `SA_HANDLER_OFF`,
`SA_MASK_OFF`, `SA_FLAGS_OFF`, and `SIGACTION_SIZE` (24 on
macOS, 32 on Linux). Callers reserve the struct with
`resb SIGACTION_SIZE` and write field-by-field via the
offsets — no host-side struct definition, no packed layout
assumption.

The subtle part is what happens when the handler returns.
The kernel stacks a signal frame on entry; that frame has
to be unwound before the interrupted instruction can
resume. The two platforms disagree on who supplies the
unwinder:

- **Linux** requires the caller to set `SA_RESTORER` in
  `sa_flags` and point `sa_restorer` at a userspace
  trampoline that invokes `SYS_rt_sigreturn`. libsig ships
  one at [`sig_restorer`](../libs/sig/util/sig-restorer.asm)
  — a three-instruction stub whose only job is to make that
  syscall. Omit it and the process crashes on handler
  return.
- **macOS** injects the trampoline itself. libsig ships an
  `sa_tramp` for callers that want to install a handler
  through the same code path as Linux; the kernel calls it
  with the standard `(handler, style, sig, info, uctx)`
  signature.

The [`42-signal-handler`](../examples/42-signal-handler/)
example walks the full install — build the struct, wire in
`sig_restorer` on Linux, catch SIGPIPE — and asserts that a
write to a broken pipe reaches the handler instead of
killing the process.

For "just ignore this signal" without a handler, the
block-mask pattern via `sigprocmask` (per-signal, thread
local, no trampoline) or the per-call `MSG_NOSIGNAL` /
`SO_NOSIGPIPE` socket flags remain the smaller tools.

## See also

- [`libs/sig/`](../libs/sig/) — the archive with all the
  sigprocmask / sigpending wrappers and sigset helpers.
- [`27-libraries.md`](27-libraries.md) — the archive index
  this chapter is a companion to.
- [`examples/38-signal-block/`](../examples/38-signal-block/)
  — the runnable that exercises the mask + pending story.
- [`examples/42-signal-handler/`](../examples/42-signal-handler/)
  — the runnable that installs a SIGPIPE handler through
  `sigaction`, using `sig_restorer` on Linux.

## Next

- Back to [docs/README.md](README.md).
