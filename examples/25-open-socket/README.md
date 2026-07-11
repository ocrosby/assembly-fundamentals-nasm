# 25 — open-socket

Create a TCP socket by calling `socket(AF_INET, SOCK_STREAM, 0)`
from [`libs/sock/libsock.a`](../../libs/sock/), then release the
file descriptor with `close`. Builds on
[24-static-link](../24-static-link/) by pointing the linker at a
different archive from the same repository.

## Introduces

- **`libsock.a` as a link target.** Where 24 linked against
  `libs/asm/libasm.a`, this example depends on
  `libs/sock/libsock.a`. The Makefile mechanics are unchanged —
  same `make -C` to build the dependency, same `extern` in the
  source, same `ld` invocation — only the `LIB :=` line moves.
  Every subsequent socket example uses this exact pattern.
- **`socket(2)`.** The first BSD-sockets call: allocate a
  communication endpoint of a given family, type, and protocol,
  and return an fd. Nothing is connected or bound yet — the
  socket is a bare endpoint waiting for further calls (`bind`,
  `connect`, `listen`, …) to give it a role.
- **A file descriptor that is not backed by a filesystem
  path.** Every fd example so far (09–11) came from
  `sys_open` on a path. A socket fd works with the same
  `read` / `write` / `close` syscalls but has no name on disk.

## Choice of arguments

`AF_INET` (2) picks the IPv4 address family. `SOCK_STREAM` (1)
picks a reliable, ordered byte stream — TCP. The third argument
is `0`, which tells the kernel to select the default protocol
for the given family + type. For `AF_INET + SOCK_STREAM` the
default is TCP, so passing `0` here is equivalent to passing
`IPPROTO_TCP` (6). Both constants are 2 and 1 respectively on
macOS and Linux, so no `%ifdef` branch is needed.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=0`. The program prints nothing — success is
signalled by the exit code. On failure (an unlikely
`ENFILE`/`EMFILE` at the fd-limit ceiling), the exit code is 1.

## Why this matters going forward

Everything the socket examples do next is one more syscall
downstream of this fd:

- `bind(fd, sockaddr, len)` gives the socket a local address
- `listen(fd, backlog)` marks it as a passive listener
- `accept(fd, ...)` blocks until a client connects and returns a
  fresh fd for the connection
- `connect(fd, sockaddr, len)` initiates an outgoing connection
- `read` / `write` on the connection fd move bytes
- `close` releases each fd when done

Every one of those wrappers is already in `libs/sock/`. The
later examples in this sequence dial each one in, one at a time.

## Next

- Back to [examples/README.md](../README.md).
