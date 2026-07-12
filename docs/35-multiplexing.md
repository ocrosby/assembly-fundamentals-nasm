# Multiplexing with poll

A blocking read on one fd stalls every other fd the process
cares about. `poll(2)` is the portable answer: hand it a list
of fds and it returns as soon as any one of them is ready, or
after a timeout, whichever comes first. libsock exports it
directly — no wrappers, because the syscall is already the
useful shape.

## The problem multiplexing solves

A server that accepts more than one connection cannot afford
to block on any single one. A tool that watches both a
network socket and a timer cannot poll them by hand without
burning CPU. The kernel already knows which fds have data
waiting; `poll` is how you ask it, and how you wait until the
answer changes.

## `struct pollfd`

Each entry is 8 bytes, identical on macOS and Linux:

| Offset | Field     | Width | Written by |
| -----: | --------- | ----: | ---------- |
| +0     | `fd`      | i32   | caller     |
| +4     | `events`  | i16   | caller     |
| +6     | `revents` | i16   | kernel     |

`events` is the set of conditions you want to wait for.
`revents` is what actually fired — the kernel writes it on
return, so reset it to zero before each call if you want the
readback to reflect only this call.

## The call

```
poll(fds, nfds, timeout_ms)
  rdi = pointer to struct pollfd array
  rsi = number of entries
  rdx = timeout in milliseconds
  rax = > 0 : count of entries whose revents is non-zero
        = 0 : timeout expired with no activity
        < 0 : -errno (interrupted, invalid fd, …)
```

The return value is a *count*, not a bitmap. Walk the array
and inspect each `revents` to find which fds fired.

## Timeout semantics

| `timeout_ms` | Behavior                                          |
| -----------: | ------------------------------------------------- |
|          -1  | Block indefinitely until an event arrives.        |
|           0  | Poll once; return immediately (0 or count).       |
|         > 0  | Block up to that many milliseconds, then return 0. |

libtime's `sleep_ms` is built on the `poll(NULL, 0, ms)` form
of the third row — a poll with no fds is a portable sleep.

## Events worth requesting

| Flag       | Meaning                                       |
| ---------- | --------------------------------------------- |
| `POLLIN`   | Next `read` will not block.                   |
| `POLLOUT`  | Next `write` will not block.                  |
| `POLLERR`  | Error condition (kernel sets in `revents`).   |
| `POLLHUP`  | Peer hung up (kernel sets in `revents`).      |
| `POLLNVAL` | fd is not open (kernel sets in `revents`).    |

`POLLERR`, `POLLHUP`, and `POLLNVAL` are always reported
whether you asked for them or not. Set only the events you
actually want to wait for; the kernel fills in the rest.

## What poll does not tell you

- *How much* is ready. `POLLIN` means "at least one byte is
  available"; the follow-up `read` may still be short.
- *Which end* hung up. `POLLHUP` on a socket does not
  distinguish between local and remote close — you find out
  by reading, which returns 0 or `-ECONNRESET`.
- *Level vs edge triggering*. `poll` is level-triggered:
  as long as the condition holds, every subsequent call
  reports it. This is the safer default; `epoll` and
  `kqueue` add edge modes for high-fanout workloads.

## Platform successors

`poll` scales linearly with the number of watched fds —
tolerable up to a few hundred, painful past that. Both
kernels ship a native replacement: Linux has `epoll` (a
kernel-maintained set that only reports changes),
macOS has `kqueue` (a filter-based event queue with the
same asymmetric shape). libsock stops at `poll` on
purpose. It is the largest portable common denominator;
`epoll` and `kqueue` are platform-specific enough that
they belong in the caller, not the archive.

## See also

- [`libs/sock/syscall/poll.asm`](../libs/sock/syscall/poll.asm)
  — the wrapper is a single `SYSCALL_NORM`; the shape lives
  in the kernel.
- [`32-sock.md`](32-sock.md) — the server dance that
  every non-trivial poll loop wraps around.
- [`33-time.md`](33-time.md) — `sleep_ms` is `poll(NULL, 0, ms)`,
  the same syscall used as a timer.
- [`examples/46-nonblock`](../examples/46-nonblock/) — the
  reason poll matters: once `O_NONBLOCK` is set, a
  would-be-blocking read returns `-EAGAIN` and you need a
  way to wait for readiness.
- [`examples/49-poll`](../examples/49-poll/) — the runnable
  that exercises both the timeout and the ready path on a
  single pipe.

## Next

- Back to [docs/README.md](README.md).
