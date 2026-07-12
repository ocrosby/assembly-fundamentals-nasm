# 49 — poll-pipe

Multiplex on a single pipe with `poll(2)`. Poll first with an
empty pipe — it times out after 50 ms and returns 0. Write one
byte into the write end, poll again — the read end fires
`POLLIN` and poll returns 1. Two consecutive polls exercise
both the timeout and the ready paths of the same call.

First runnable that uses libsock's `poll`. Polling is the
portable event-loop primitive on POSIX; every server that
multiplexes more than one fd goes through `poll`, `select`,
or a platform-specific replacement (`epoll` on Linux,
`kqueue` on macOS — both outside libsock's scope).

## Introduces

- **`poll(fds, nfds, timeout_ms)` (libsock).** Blocks until at
  least one of `nfds` file descriptors is ready or `timeout_ms`
  elapses. Returns the number of ready fds, `0` on timeout, or
  a negative errno.
- **`struct pollfd` layout** (identical on macOS and Linux):
  ```
  +0   fd       (i32)
  +4   events   (i16)   ; what we ask about (POLLIN, POLLOUT, ...)
  +6   revents  (i16)   ; what poll writes back
  ```
  Total 8 bytes. `events` names what you care about; poll fills
  `revents` on return with the subset that actually fired.
- **The timeout / ready dichotomy.** The same call returns 0 on
  timeout and >0 on activity; `revents & POLLIN` distinguishes
  which fd fired when there are several.

## Program flow

```
pipe(pipefd)
fds[0] = { fd = pipefd[0], events = POLLIN, revents = 0 }
poll(fds, 1, 50)                        → 0 (empty pipe, timeout)
write(pipefd[1], "x", 1)
poll(fds, 1, 500)                       → 1 (POLLIN in revents)
assert fds[0].revents & POLLIN
close(pipefd[0]); close(pipefd[1])
exit(42)
```

## Why one pipe and two polls?

Every non-trivial server multiplexes many fds — but the atom
being introduced here is the poll call itself. Testing both
outcomes (timeout, ready) on a single fd keeps the demo
hermetic: no fork, no network, no external process. Adding
more fds only multiplies `nfds` and array indices; the poll
mechanics stay identical.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
