# 27 — listen-socket

Open a TCP socket via
[`libs/sock/libsock.a`](../../libs/sock/), bind it to
`127.0.0.1:0`, then mark it **passive** with `listen(fd, 8)`
so it is ready to accept incoming connections. Close the fd
and exit. Builds on [26-bind-socket](../26-bind-socket/) by
adding one new atomic concept: the `listen` state transition.

## Introduces

- **`listen(2)`.** The state transition that turns a bound
  socket into a passive listener. Before `listen`, the socket
  has an address but no place to queue incoming connections;
  after `listen`, the kernel accepts SYN packets on its behalf
  and holds a queue of pending connections for the next
  `accept()`. Without `listen`, `accept` immediately returns
  `EINVAL`.
- **The listen backlog.** The second argument to `listen` is
  the maximum number of connections the kernel will queue
  before returning `ECONNREFUSED` (Linux) or dropping SYNs
  (macOS) to further clients. `8` is enough to make the
  behavior distinguishable in a demo without wasting kernel
  memory; production servers pick a value tuned to their
  expected concurrency.

## What this doesn't do

The program closes the fd immediately after `listen` returns.
Nothing accepts, nothing reads, nothing writes — the
observable behavior is identical to just running
[`26-bind-socket`](../26-bind-socket/). The point is the
state change, not any user-visible side effect. Example 28
onward will add `accept()` and turn this into a real one-shot
listener that can talk to a client.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=0`. As with the other socket examples,
success is signalled by the exit code — the program prints
nothing.

## Next

- Back to [examples/README.md](../README.md).
