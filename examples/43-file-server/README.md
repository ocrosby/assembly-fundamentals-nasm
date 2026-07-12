# 43 — file-server

Serve a file over a TCP socket with `file_copy_stream`. The
parent seeds `/tmp/nasm-file-server.txt`, binds a loopback
listener, forks. The child accepts one connection, calls
`file_copy_stream(path, conn_fd)`, and exits. The parent
connects, reads until 12 bytes arrive, byte-compares against
the reference, and exits 42.

First runnable that combines libio v1.15's
`file_copy_stream` with a libsock server.

## Introduces

- **`file_copy_stream` used for real.** Where 41-logger
  and 39-number-store kept the writes on a local file,
  this example proves the helper's second use case:
  sending a file over a caller-provided fd — the "send
  this file over this socket" pattern that motivated
  shipping the helper.
- **Three archives in one example.** libsock (socket +
  bind + listen + accept + connect + close + read +
  getsockname), libio (file_write_all + file_copy_stream),
  libproc (fork + wait4). All three link cleanly because
  none of them call into each other.

## Program flow

```
parent:
    file_write_all(path, "HELLO WORLD!", 12)  ; seed
    socket, bind, getsockname, listen         ; listener fd
    fork()
    ├── child (server):
    │       accept()                           ; conn_fd
    │       file_copy_stream(path, conn_fd)
    │       close(conn_fd); close(listener)
    │       exit(0)
    └── parent (client):
            socket, connect
            read loop until 12 bytes received
            byte-compare buf vs "HELLO WORLD!"
            wait4(child); verify exit == 0
            exit(42)
```

## Coordination pattern

Same as [29-server-client](../29-server-client/) and
[34-echo-server](../34-echo-server/): bind before fork,
`getsockname` to read the resolved port from the kernel,
patch the client sockaddr, then fork so both sides share
the same port constant. Backlog of 1 is enough — the child
accepts one connection.

## Why bytes come back the way they went out

`file_copy_stream` writes the file's bytes to `conn_fd` and
returns. The TCP peer sees the write followed by the child
closing its end, which sends FIN. The parent's `read` loop
receives the 12 bytes and, on the next iteration, would see
EOF via `rax == 0`. This example stops the loop as soon as
`msg_len` bytes have accumulated so the "read until EOF"
behavior isn't required for correctness.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
