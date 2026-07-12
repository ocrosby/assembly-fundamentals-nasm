# 38 — signal-block

First runnable that uses libsig. Blocks SIGPIPE, writes to a
broken pipe (which normally terminates the process), verifies
via `sigpending` that the signal was queued instead, then
exits 42.

## Introduces

- **`sigprocmask(SIG_BLOCK, ...)` (libsig v1.0).** From the
  point the mask is installed, the kernel queues signals in
  the mask instead of delivering them.
- **`sig_zero` + `sig_add` (libsig v1.1).** Build a mask by
  name instead of writing `1 << (SIGPIPE - 1)` inline.
- **`sigpending` + `sig_test`.** Query which blocked signals
  have been raised while masked. This is what turns "block a
  signal and pretend it never happened" into "block a signal
  and know whether it was raised."
- **The pipe / broken-writer hazard.** Writing to a pipe
  whose read end is closed normally kills the process with
  signal 13 (SIGPIPE). This example turns that hazard into
  a recoverable errno (`-EPIPE`) using the block-mask
  pattern.

## Program flow

```
sig_zero(mask); sig_add(mask, SIGPIPE)
sigprocmask(SIG_BLOCK, mask, NULL)          → SIGPIPE now queued, not delivered
pipe(pipefd)                                 → read/write pair
close(pipefd[0])                             → sever the read side
write(pipefd[1], "orphaned bytes", 14)       → returns -EPIPE, queues SIGPIPE
sigpending(pending)                          → 0
sig_test(pending, SIGPIPE)                   → 1
close(pipefd[1])
exit(42)
```

Do **not** unblock SIGPIPE before exit. Its default action
is to terminate the process, and delivering a queued
SIGPIPE now would make the process exit `141` (128 + 13)
instead of `42`. The pending signal is discarded on process
exit anyway.

## Why it works

Without the block-mask, the `write` in step 5 would deliver
SIGPIPE synchronously and the process would die before it
could observe the -EPIPE return or check `sigpending`. Every
program that writes to sockets or pipes has to make one of
three choices about this: ignore SIGPIPE entirely (install
`SIG_IGN` via `sigaction` — deferred until libsig grows the
SA_RESTORER trampoline), block it during specific critical
sections (this example), or use send flags that suppress
the signal per-call (Linux's `MSG_NOSIGNAL`, macOS's
`SO_NOSIGPIPE`).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
