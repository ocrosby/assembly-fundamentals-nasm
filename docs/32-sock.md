# Sockets and networking

The [`libsock`](../libs/sock/) archive is the "talk to
another process, on this machine or another" piece of the
toolkit. It covers the Berkeley sockets syscalls in one
subdirectory, the `<arpa/inet.h>` byte-order and text
helpers in another, and a handful of composed helpers on
top of both.

## `struct sockaddr_in` and the SIN_HEADER trick

Every AF_INET call takes a `struct sockaddr_in`. On Linux the
layout is:

```
+0   sin_family   (u16, host order) = AF_INET (2)
+2   sin_port     (u16, network order)
+4   sin_addr     (u32, network order)
+8   sin_zero     (8 bytes, must be zero)
```

macOS BSD prepends a `sin_len` byte:

```
+0   sin_len      (u8) = 16
+1   sin_family   (u8) = AF_INET (2)
+2   sin_port     (u16, network order)
+4   sin_addr     (u32, network order)
+8   sin_zero     (8 bytes)
```

Both platforms put the *interesting* fields at the same
offsets — port at +2, address at +4. The two bytes at +0..1
differ.

The example sequence and the sock smokes handle this with a
`SIN_HEADER` macro: `0x0210` on macOS (sin_len=16 in the low
byte, sin_family=AF_INET in the high byte, little-endian) and
`0x0002` on Linux (sin_family alone). Every `sockaddr_in` in
the repo starts with `dw SIN_HEADER` and the port/address
fields are written directly at their platform-agnostic
offsets.

## Byte order — `htons`, `htonl`, `ntohs`, `ntohl`

Ports and addresses travel over the wire in network byte
order (big-endian). x86-64 is little-endian, so any
conversion between "value the CPU understands" and "bytes on
the wire" runs through `htons` (host → net, 16-bit) or
`htonl` (32-bit). `ntohs` / `ntohl` go the other way. Each is
a `bswap` under the hood — one instruction.

The example sequence often builds sockaddrs with the byte
values written directly (`db 127, 0, 0, 1` and
`dw <port_high>, <port_low>`) because it is cheaper than
constructing the u32 and then byte-swapping it. When a value
does come out of a syscall or arithmetic, byte-order helpers
are what convert it.

## Short writes are the caller's problem — `send_all`

TCP `write` and `send` are allowed to return fewer bytes than
requested at any time; the caller has to loop until the whole
payload lands. libsock ships this loop as `send_all`:

```
send_all(fd, buf, len) → 0 or negative errno
```

The pattern shows up everywhere — 34-echo-server, 43-file-
server, libio's `file_write_all`. `send_all` is the socket
version of that same "loop until done" shape.

## Server dance — `socket` + `bind` + `listen` + `accept`

The four-step server pattern is spelled out in
[27-listen-socket](../examples/27-listen-socket/) and
composed into one call by libsock's `server_bind_listen`
helper. Callers who want the raw sequence use the individual
wrappers; callers who want "give me a listener on this
address" call the composed helper and get a listen-ready fd
back.

`accept` returns a *new* fd for the incoming connection. The
listener stays live for future accepts. Servers usually
`fork` after accept and let the child talk on the accepted fd
— that's the pattern
[34-echo-server](../examples/34-echo-server/) and
[43-file-server](../examples/43-file-server/) both use.

## Client dance — `socket` + `connect`

The two-step client pattern is composed as
`client_connect(sockaddr)`, which returns a connected fd.
Callers pass the sockaddr they want to reach and get a fd
that's already through the handshake.

## `getsockname` — reading the resolved port back

Binding to port 0 asks the kernel to pick a free port.
`getsockname` reads the resolved port from the listener fd
after `bind` runs — that's how
[29-server-client](../examples/29-server-client/) and every
subsequent server example coordinate parent and child on the
same port without hard-coding one.

## See also

- [`libs/sock/`](../libs/sock/) — the full archive with
  every syscall wrapper and the composed helpers.
- [`27-libraries.md`](27-libraries.md) — the archive
  index this chapter is a companion to.
- [`examples/34-echo-server`](../examples/34-echo-server/)
  and [`examples/43-file-server`](../examples/43-file-server/)
  — runnables that exercise the server dance end to end.

## Next

- Back to [docs/README.md](README.md).
