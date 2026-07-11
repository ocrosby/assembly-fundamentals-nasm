# 29 — server-client

A complete TCP round trip inside a single process image. The
program forks; the parent listens and reads, the child
connects and writes `"PING"`. On success both exit 0.
Combines everything the socket sequence (25–27) and the fork
example (28) have built up.

## Introduces

- **Linking against two archives at once.** The Makefile
  lists both `libs/sock/libsock.a` and `libs/proc/libproc.a`
  on the `ld` command line — the first example in the
  sequence to do so. Static-archive linkers scan
  left-to-right; neither archive references symbols in the
  other, so the order does not matter here.
- **`accept(2)` and `connect(2)`.** The two socket calls that
  move a socket from "there is a listening endpoint" to
  "there is a live byte-stream connection". Parent's
  `accept` blocks until the child's `connect` completes.
- **`read(2)` and `write(2)` over a socket.** The same
  syscalls the file examples (09–11) used for disk I/O,
  now moving bytes through a TCP connection. Parent asks
  for exactly 4 bytes; child sends exactly 4 bytes. No
  framing protocol beyond the byte count.
- **`getsockname(2)` for kernel-picked ports.** Bind uses
  port 0 so the kernel picks a free ephemeral port; the
  program reads the resolved port back with `getsockname`
  and patches it into the client-side sockaddr before
  forking. Both processes then see the same port via
  copy-on-write.
- **Cross-process synchronization via the accept queue.**
  `listen(fd, 1)` sets the queue depth. Even if the child's
  `connect` runs before the parent's `accept`, the
  connection queues on the kernel side and the later
  `accept` dequeues it. No explicit sleep or handshake is
  needed.

## The four-byte payload

`"PING"` sits in `.data` as a plain byte literal. The parent
verifies the four bytes it read by comparing them against a
precomputed little-endian dword literal: `db "PING"` places
the bytes `0x50 0x49 0x4E 0x47` in memory, so reading them
back as a dword yields `0x474E4950`. That is the value the
`cmp dword [recvbuf], PING_LE` line checks against.

## Program flow

```
   parent                              child
   ------                              -----
   socket()  → listener fd
   bind()    → 127.0.0.1:0
   getsockname()  read the port
   listen()  → passive
   fork()  ─────────────┬──────────────►
                        │                close(listener_fd)
   accept()  waits      │                socket()  → client fd
                        │                connect(127.0.0.1:port)
                        │                write("PING")
                        │                close(client_fd)
   accept() returns     │                _exit(0)
   read(4 bytes)        │
   verify == "PING"     │
   close both fds       │
   wait4(child_pid)     │
   exit(0)              │
```

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=0`. The program produces no output — success
is signalled by the exit code. Any error in either branch
(the parent's `accept` failing, the child's `connect` being
refused, the read returning wrong bytes) exits 1.

## Next

- Back to [examples/README.md](../README.md).
