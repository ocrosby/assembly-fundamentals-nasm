# 42 — signal-handler

Install a custom SIGPIPE handler, then trigger SIGPIPE three
times by writing to a pipe whose read end is closed. The
handler increments a counter; the parent verifies the
counter reached 3 before exiting. On Linux the handler is a
real function running via libsig v1.3's `sig_restorer`
trampoline; on macOS the disposition falls back to `SIG_IGN`
and the counter is bumped from the `-EPIPE` return instead.

First runnable that uses libsig v1.3's `sig_restorer`
trampoline end to end.

## Introduces

- **`sig_restorer` (libsig v1.3, Linux only).** The
  SA_RESTORER trampoline that lets a handler function
  `ret` cleanly. Without it the handler's return address
  is garbage from the signal frame and the process
  crashes.
- **Handler + observation pattern.** Where
  [`38-signal-block`](../38-signal-block/) queued SIGPIPE
  via `sigprocmask` and only observed *pending*, this
  example **catches** the delivery in a handler that runs
  and returns normally — the whole point of shipping a
  real trampoline.
- **Cross-platform fallback.** Until libsig v1.4 (or later)
  ships macOS's sa_tramp trampoline, this example falls
  back to `SIG_IGN` on macOS. The observation site changes
  (kernel-side handler vs. userland `-EPIPE` return) but
  the exit code is the same.

## Program flow (Linux path)

```
act.sa_handler   = handler
act.sa_flags    |= SA_RESTORER
act.sa_restorer  = sig_restorer
sigaction(SIGPIPE, act, NULL)         → 0

pipe(pipefd); close(pipefd[0])

for i in 0..2:
    write(pipefd[1], "x", 1)          → -EPIPE
    ; handler runs, counter += 1

assert counter == 3
exit(42)
```

## Program flow (macOS path)

```
act.sa_handler = SIG_IGN
sigaction(SIGPIPE, act, NULL)         → 0

pipe(pipefd); close(pipefd[0])
counter = 0

for i in 0..2:
    write(pipefd[1], "x", 1)          → -EPIPE
    counter += 1                       (from -EPIPE, not handler)

assert counter == 3
exit(42)
```

Same shape, different observation site. Both exit 42.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42` on both platforms.

## Next

- Back to [examples/README.md](../README.md).
