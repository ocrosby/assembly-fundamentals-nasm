# 26 — bind-socket

Open a TCP socket via [`libs/sock/libsock.a`](../../libs/sock/),
build a `struct sockaddr_in` for **loopback (127.0.0.1) on port
0**, call `bind`, and close the fd. Builds on
[25-open-socket](../25-open-socket/) by adding one new atomic
concept: giving the socket a local address.

## Introduces

- **`bind(2)`.** The step every server-side socket takes: hand
  the kernel a `(family, port, address)` tuple so the fd
  becomes bound to a specific listening endpoint. On its own
  a bound socket does nothing observable — no client can
  connect until `listen` and `accept` are added (examples 27
  and beyond).
- **Manual `struct sockaddr_in` construction.** All 16 bytes
  are written directly in the `.rodata` section. The layout
  differs between macOS and Linux in the first two bytes
  only: BSD carries an `sin_len` field at offset 0 that
  Linux does not. A single `dw` per platform via `%ifdef`
  handles the split.
- **Network byte order without `htons`/`htonl`.** By writing
  the address byte-by-byte (`db 127, 0, 0, 1`) and using
  port 0 (which is byte-identical in both orders), the
  example sidesteps the host-to-network conversion. Byte
  order becomes an issue as soon as you pick a non-zero port
  — that's a topic for a later example.

## Why port 0?

Passing `sin_port = 0` tells the kernel: "pick any free
ephemeral port." This is the standard trick for test code
and short-lived sockets — the process gets a free port
without ever competing with another user of the machine.
Real servers pick a specific port (typically via a config
value); example 27 or beyond will introduce that once
`listen` is on the table.

## `sockaddr_in` on macOS vs Linux

| offset | Linux                     | macOS                                 |
|--------|---------------------------|---------------------------------------|
| 0      | `sin_family` low byte     | `sin_len = 16`                        |
| 1      | `sin_family` high byte    | `sin_family = AF_INET`                |
| 2..3   | `sin_port`   (u16, net)   | `sin_port`   (u16, net)               |
| 4..7   | `sin_addr`   (u32, net)   | `sin_addr`   (u32, net)               |
| 8..15  | `sin_zero`   (8 bytes)    | `sin_zero`   (8 bytes)                |

Little-endian storage collapses the platform difference into
one 16-bit value at offset 0 — see the `SIN_HEADER` `%define`
in [`bind-socket.asm`](bind-socket.asm).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=0`. The program prints nothing — success is
signalled by the exit code, as with 25-open-socket.

## Next

- Back to [examples/README.md](../README.md).
