# 34 — echo-server

A single-process TCP echo server. Parent listens on
`127.0.0.1:0`, forks a client child, then runs an echo loop
against whatever the child sends. Child sends
`"HELLO WORLD!"`, reads it back, verifies it, closes. Parent
sees EOF, closes, `wait4`s the child, exits 42. Builds on
[29-server-client](../29-server-client/) by turning that
example's one-shot PING into a real "read → send back → until
EOF" server loop.

## Introduces

- **A real echo loop.** The parent side reads up to 64 bytes,
  and if the read returned 0 (EOF from a peer close), breaks;
  otherwise it calls `send_all` on exactly the number of bytes
  it read. That is what makes it a "server" instead of a
  one-message exchange — the parent has no idea how many bytes
  the client will send or in how many chunks, and doesn't
  need to.
- **First real user of libsock v1.4's `send_all`.** For a
  12-byte "HELLO WORLD!" payload on loopback, `write` will
  almost always complete in one call — but the loop matters
  in principle and matters in production. `send_all` factors
  it out so callers stop having to think about it. Both the
  child (sending the greeting) and the parent (echoing the
  bytes) use it.
- **Port coordination via `getsockname`, patched pre-fork.**
  Same technique as [29-server-client](../29-server-client/):
  bind port 0, `getsockname` reads the kernel-picked port
  back, the value is copied into the client sockaddr before
  fork. The copy-on-write child inherits the resolved port
  without any explicit hand-off.

## Program flow

```
parent                              child
──────                              ─────
socket + bind (127.0.0.1:0)         (inherits everything via fork)
getsockname   → picked port
patch port into client_sockaddr
listen(fd, 1)
fork() ────────►
                                    close(listener_fd)
                                    socket + connect
accept                              send_all "HELLO WORLD!" (12 bytes)
loop:                               read 12 bytes back
  read up to 64                     cmp against "HELLO WORLD!"
  if 0 (EOF): break                 close (sends FIN)
  send_all(N)                       _exit(0)
close both fds
wait4(child)  → wstatus 0
exit(42)
```

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`. Any break in the chain — bind failed,
accept returned an error, send_all didn't get all bytes on
the wire, the child received corrupted bytes, wait4 saw a
non-zero wstatus — produces exit 1.

## Next

- Back to [examples/README.md](../README.md).
