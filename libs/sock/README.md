# libs/sock/

Berkeley sockets primitives packaged as the static archive
`libsock.a`. The archive tracks the syscall-backed portion of
POSIX
[`<sys/socket.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/sys_socket.h.html)
plus the byte-order and IPv4/IPv6 text-conversion helpers from
[`<arpa/inet.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/arpa_inet.h.html).

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Exported symbols

### Connection lifecycle

| Symbol         | Arguments                                                     | Returns                              |
| -------------- | ------------------------------------------------------------- | ------------------------------------ |
| `socket`       | `domain`, `type`, `protocol`                                  | fd or negative errno                 |
| `bind`         | `fd`, `addr`, `addrlen`                                       | 0 or negative errno                  |
| `listen`       | `fd`, `backlog`                                               | 0 or negative errno                  |
| `accept`       | `fd`, `addr`, `addrlen*`                                      | new fd or negative errno             |
| `connect`      | `fd`, `addr`, `addrlen`                                       | 0 or negative errno                  |
| `shutdown`     | `fd`, `how` (`SHUT_RD` / `SHUT_WR` / `SHUT_RDWR`)             | 0 or negative errno                  |
| `close`        | `fd`                                                          | 0 or negative errno                  |

### I/O

| Symbol         | Arguments                                                     | Returns                              |
| -------------- | ------------------------------------------------------------- | ------------------------------------ |
| `read`         | `fd`, `buf`, `len`                                            | bytes read (0 = EOF) or -errno       |
| `write`        | `fd`, `buf`, `len`                                            | bytes written or -errno              |
| `send`         | `fd`, `buf`, `len`, `flags`                                   | bytes sent or -errno                 |
| `recv`         | `fd`, `buf`, `len`, `flags`                                   | bytes received (0 = EOF) or -errno   |
| `sendto`       | `fd`, `buf`, `len`, `flags`, `addr`, `addrlen`                | bytes sent or -errno                 |
| `recvfrom`     | `fd`, `buf`, `len`, `flags`, `addr*`, `addrlen*`              | bytes received (0 = EOF) or -errno   |
| `sendmsg`      | `fd`, `msg`, `flags`                                          | bytes sent or -errno                 |
| `recvmsg`      | `fd`, `msg`, `flags`                                          | bytes received or -errno             |

### Options and introspection

| Symbol         | Arguments                                                     | Returns                              |
| -------------- | ------------------------------------------------------------- | ------------------------------------ |
| `getsockopt`   | `fd`, `level`, `optname`, `optval*`, `optlen*`                | 0 or negative errno                  |
| `setsockopt`   | `fd`, `level`, `optname`, `optval`, `optlen`                  | 0 or negative errno                  |
| `getsockname`  | `fd`, `addr*`, `addrlen*`                                     | 0 or negative errno                  |
| `getpeername`  | `fd`, `addr*`, `addrlen*`                                     | 0 or negative errno                  |
| `socketpair`   | `domain`, `type`, `protocol`, `sv[2]*`                        | 0 or negative errno                  |

### Multiplexing

| Symbol         | Arguments                                                     | Returns                              |
| -------------- | ------------------------------------------------------------- | ------------------------------------ |
| `select`       | `nfds`, `readfds*`, `writefds*`, `exceptfds*`, `timeout*`     | ready count or negative errno        |
| `poll`         | `fds*`, `nfds`, `timeout_ms`                                  | ready count or negative errno        |

### Byte order

| Symbol   | Arguments        | Returns                                          |
| -------- | ---------------- | ------------------------------------------------ |
| `htons`  | `u16` host order | `u16` network order (zero-extended in `rax`)     |
| `ntohs`  | `u16` net order  | `u16` host order (zero-extended in `rax`)        |
| `htonl`  | `u32` host order | `u32` network order (zero-extended in `rax`)     |
| `ntohl`  | `u32` net order  | `u32` host order (zero-extended in `rax`)        |

### IPv4 / IPv6 text ↔ binary

| Symbol         | Arguments                                     | Returns                                    |
| -------------- | --------------------------------------------- | ------------------------------------------ |
| `inet_pton4`   | `src` (NUL-terminated), `dst*` (4 bytes)      | `1` on success, `0` on parse failure       |
| `inet_ntop4`   | `src` (u32 net order), `dst*`, `dst_size`     | `dst` on success, `NULL` if `size < 16`    |
| `inet_pton6`   | `src` (NUL-terminated), `dst*` (16 bytes)     | `1` on success, `0` on parse failure       |
| `inet_ntop6`   | `src*` (16 bytes net order), `dst*`, `dst_size` | `dst` on success, `NULL` if `size < 46`  |

Parsers are strict: `inet_pton4` follows POSIX `inet_pton()`
`AF_INET` rules (no leading zeros, no octal fallback);
`inet_pton6` implements the full RFC 4291 grammar; `inet_ntop6`
emits the RFC 5952 canonical form. Buffer-size requirements are
`INET_ADDRSTRLEN` (16) for `inet_ntop4` and `INET6_ADDRSTRLEN`
(46) for `inet_ntop6`. See [`inet/README.md`](inet/) for the
exact accepted grammar, rejection cases, and canonical-form
rules.

### Composed server helpers (v1.1)

| Symbol               | Arguments                                                    | Returns                              |
| -------------------- | ------------------------------------------------------------ | ------------------------------------ |
| `server_bind_listen` | `ip_net` (u32 net order), `port_host` (u16), `backlog` (int) | fd or negative errno                 |

`server_bind_listen` composes the four syscalls that every TCP
server always makes into one call: `socket(AF_INET,
SOCK_STREAM, 0)` → `setsockopt(SO_REUSEADDR, 1)` →
`bind(sockaddr_in{ip, port}, 16)` → `listen(backlog)`. The
returned fd is ready for `accept`; on any failure after
`socket()` succeeded the fd is closed before the errno is
returned, so callers cannot leak a descriptor.

Pass `ip_net = 0` for `INADDR_ANY` (bind every interface),
`0x0100007F` for `127.0.0.1` on little-endian x86_64, or an
`inet_pton4` output for any other IPv4 literal. Pass
`port_host = 0` to let the kernel pick an ephemeral port; the
caller reads it back via `getsockname` on the returned fd.

## What is not here — DNS

`gethostbyname`, `gethostbyaddr`, `getaddrinfo`, and
`getnameinfo` are part of the Berkeley sockets API but are **not
implementable as direct syscalls**. Name resolution requires a
DNS resolver plus name-service switch (`/etc/nsswitch.conf`) plus
NSS module loading — thousands of lines of code that live inside
`libc` for a reason. Callers of `libsock.a` supply numeric
addresses (via `inet_pton4` / `inet_ntop4` for IPv4 or
`inet_pton6` / `inet_ntop6` for IPv6) and numeric ports.

## Calling convention notes

The [shared `libs/` conventions](../README.md) apply: System V
AMD64 ABI, callee-saved `rbx` / `rbp` / `r12`–`r15`, uniform
non-negative-on-success / negative-errno-on-failure contract.
Two syscall-side subtleties on top of that — moving the SysV
4th argument from `rcx` into the syscall ABI slot `r10`, and
normalizing macOS's carry-flag error convention to Linux's
`-errno` shape — live inside the wrappers themselves. See
[`syscall/README.md`](syscall/) for the `SYSCALL_ARG4` and
`SYSCALL_NORM` macros that implement them and the list of
wrappers each one covers.

## Build

### macOS

```bash
make                                # produces libs/sock/libsock.a
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the object files into
`libsock.a` with `ar rcs`.

### Linux

```bash
make                                # produces libs/sock/libsock.a
```

On Linux the same `make` assembles with `nasm -f elf64`.

## Linking against `libsock.a`

In the consumer's `.asm`:

```nasm
extern socket, bind, listen, accept, connect, shutdown, close
extern read, write, send, recv, sendto, recvfrom, sendmsg, recvmsg
extern getsockopt, setsockopt, getsockname, getpeername, socketpair
extern select, poll
extern htons, htonl, ntohs, ntohl
extern inet_pton4, inet_ntop4, inet_pton6, inet_ntop6
```

In the consumer's `Makefile`, append the archive to the link
line. For a consumer at `examples/NN-slug/`, the path is
`../../libs/sock/libsock.a`:

```makefile
LIBSOCK := ../../libs/sock/libsock.a

$(BIN): $(OBJ) $(LIBSOCK)
	$(LD) $(OBJ) $(LIBSOCK) -o $(BIN)
```

Building the consumer does not automatically build the archive;
run `make -C ../../libs/sock` first.

## Test

```bash
make test                           # requires python3
```

`make test` builds `libsock.a` and `libasm.a`, then runs eight
smoke tests in sequence via the harness in [`test/`](test/).
Together they call every one of the 31 exported symbols on at
least one success path; every syscall wrapper on at least one
failure path (which is what actually exercises the macOS
`SYSCALL_NORM` `neg rax` branch — the success paths never do);
and every conditional branch inside the four pure-computation
files in [`inet/`](inet/) (`inet_pton4`, `inet_ntop4`,
`inet_pton6`, `inet_ntop6`) at least once. The branch-coverage
audit that produced this suite also caught a real off-by-one
in `inet_pton6`'s dotted-quad path that used to corrupt the
caller's `r15` on inputs like `1:2:3:4:5:6:7:1.2.3.4`; the
regression case is sub-check `q` in `inet6-smoke`.

- [`inet4-smoke.asm`](test/inet4-smoke.asm) — the byte-order
  helpers (`htons`, `htonl`, `ntohs`, `ntohl`) and the strict
  IPv4 text conversion (`inet_pton4`, `inet_ntop4`) across
  every documented rejection case (out-of-range octet, leading
  zero, trailing garbage, missing octet) plus a full round-trip.
- [`inet6-smoke.asm`](test/inet6-smoke.asm) — `inet_pton6` and
  `inet_ntop6` across 33 sub-checks: 9 successful parses, 14
  rejections, 9 canonical outputs (including the RFC 5952
  first-tie compression rule and the IPv4-mapped tail form),
  the buffer-too-small `NULL` return, and a pton→ntop→pton
  round-trip.
- [`ipc-smoke.asm`](test/ipc-smoke.asm) — creates an
  `AF_UNIX SOCK_STREAM` pair via `socketpair()`, then exercises
  `send`, `recv`, `sendto`, `recvfrom`, `sendmsg`, `recvmsg`,
  `select`, and `poll` against the pair. Fully in-process — no
  Python peer needed.
- [`fail-smoke.asm`](test/fail-smoke.asm) — calls every one of
  the 22 syscall wrappers with args designed to force a failure
  (`fd = 999999`, an unassigned address family, or a negative
  `nfds`) and verifies each returns a negative errno. This is
  what actually runs the `neg rax` line inside `SYSCALL_NORM`
  on macOS. On Linux the same call verifies each wrapper
  correctly propagates the kernel's negative errno.
- [`bind-listen-smoke.asm`](test/bind-listen-smoke.asm) — the
  v1.1 composed helper. Calls `server_bind_listen` with
  `INADDR_ANY` and `127.0.0.1` in turn, each time verifying
  the returned fd is non-negative and closes cleanly. Proves
  the socket + setsockopt + bind + listen composition is a
  drop-in replacement for the four-syscall server prologue
  and does not leak the fd on any interior failure.
- [`tcp-smoke.asm`](test/tcp-smoke.asm) + `server.py` —
  end-to-end TCP client. Python loopback server on an ephemeral
  port; assembly client goes through `socket` / `connect` /
  `write` / `read` / `close` and receives the banner.
- [`server-smoke.asm`](test/server-smoke.asm) +
  `server-client.py` — end-to-end TCP server. Assembly server
  binds to `127.0.0.1:0`, learns its own port via
  `getsockname`, verifies via `getsockopt(SO_TYPE)` that the
  socket is `SOCK_STREAM`, accepts one client, verifies the
  peer via `getpeername`, reads, writes, does `shutdown(SHUT_WR)`,
  closes. Python client drives the exchange over the port the
  server published on stdout. Exercises `setsockopt`, `bind`,
  `listen`, `getsockname`, `getsockopt`, `accept`, `getpeername`,
  and `shutdown` — the remaining wrappers not touched by the
  other tests.
- [`c-smoke.c`](test/c-smoke.c) — compatibility smoke, not a
  coverage test. Verifies `libsock.a` is linkable and callable
  from a normal C toolchain: manually declares the archive's
  symbols with GCC `__asm__` labels (to bypass Mach-O's
  underscore-prefix convention that would otherwise hide our
  NASM-emitted bare names), links `libsock.a` before libc, and
  asserts `htons`/`htonl`/`ntohs`/`ntohl` byte-swap correctly,
  `inet_pton4`/`inet_ntop4`/`inet_pton6`/`inet_ntop6`
  round-trip, and `socket(AF_INET, SOCK_STREAM, 0) + close(fd)`
  returns a valid fd. If the archive were ever broken for C
  consumers (ABI mismatch, unresolvable symbols, wrong return
  register), this test catches it.

All server-side sockets are loopback-only, single-connection,
and timeout-bounded, so the tests never reach the network and
cannot hang. On success the runner prints one line per test:

```text
PASS: inet4-smoke    output=[PASS]
PASS: inet6-smoke    output=[PASS]
PASS: ipc-smoke      output=[PASS]
PASS: fail-smoke     output=[PASS]
PASS: bind-listen-smoke output=[PASS]
PASS: tcp-smoke      output=[TCP-OK]
PASS: server-smoke   output=[PORT:<n>]
PASS: c-smoke        output=[PASS]
```

All three run on both macOS and Linux under CI.

## Source layout

Wrappers are split into three subdirectories that mirror how the
code actually works:

- [`syscall/`](syscall/) — 22 kernel-syscall wrappers plus their
  shared `syscall.inc` header. Every file is a three-to-five
  instruction shim over a single syscall. As of v1.1 the header
  also exports shared socket-domain constants (`AF_INET`,
  `SIN_HEADER`, `SOL_SOCKET`, `SO_REUSEADDR`, `SO_TYPE`,
  `SO_RCVTIMEO`) so composed helpers do not redefine them.
- [`inet/`](inet/) — 8 pure-computation helpers from POSIX
  `<arpa/inet.h>` (byte-order + IPv4/IPv6 text conversion). No
  kernel calls, no shared header.
- [`util/`](util/) — v1.1 composed helpers that string several
  syscall wrappers together into a single call. Currently one
  entry: `server_bind_listen`.

Each exported symbol lives in a same-named file (`socket.asm`
exports `socket`, `htons.asm` exports `htons`, and so on). The
archive `libsock.a` is flat by symbol regardless of source
layout, so consumers still `extern` and link the same way.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`). Consumers of
  `libsock.a` typically also link `libasm.a` to print the bytes
  they receive.
- [`../../examples/20-shared-lib/`](../../examples/20-shared-lib/)
  — the example that first demonstrates linking against an
  external library.
