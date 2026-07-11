# libs/sock/

Berkeley sockets primitives packaged as the static archive
`libsock.a`. Every routine is a direct syscall wrapper — no libc,
no libSystem call, no allocation. The archive tracks the
syscall-backed portion of the POSIX
[`<sys/socket.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/sys_socket.h.html)
family plus the byte-order and IPv4 address-conversion helpers
from [`<arpa/inet.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/arpa_inet.h.html).

See [`../README.md`](../README.md) for the conventions shared by
every archive in `libs/` — calling convention, error convention,
and the no-libc policy.

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

`inet_pton4` is strict: it rejects leading zeros ("01.2.3.4"),
out-of-range octets ("1.2.3.256"), missing octets ("1.2.3"), and
trailing garbage ("1.2.3.4.5"). This matches POSIX `inet_pton()`
for `AF_INET` and diverges deliberately from the older
`inet_aton()`, which treats a leading `0` as octal.

`inet_pton6` supports the full RFC 4291 grammar: 1–8 hex groups
of 1–4 digits, mixed case, `::` compression (at most once,
expanding to at least one zero group), leading `::` and trailing
`::`, and the IPv4-mapped tail form `::ffff:192.0.2.1`. It
rejects the bare-IPv4 form (`1.2.3.4` with no `::` prefix),
scope IDs (`%eth0`), a single leading colon that is not part of
`::`, a trailing colon, and any group longer than four hex
digits.

`inet_ntop6` emits RFC 5952 canonical form: lowercase hex, no
leading zeros within a group, longest run of two or more zero
groups compressed to `::` (first run wins on tie), and
IPv4-mapped addresses printed as `::ffff:a.b.c.d`. The
destination buffer must be at least `INET6_ADDRSTRLEN` (46
bytes: `ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255` plus NUL).

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

Every routine follows the System V AMD64 ABI: arguments in `rdi`,
`rsi`, `rdx`, `rcx`, `r8`, `r9`; return value in `rax`.
Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) are preserved.

Two subtleties the syscall wrappers handle for you:

- **4th-argument shuffle.** The kernel's syscall ABI expects the
  4th argument in `r10`, not `rcx` (the syscall instruction
  clobbers `rcx`). Wrappers with four or more arguments — `send`,
  `recv`, `sendto`, `recvfrom`, `getsockopt`, `setsockopt`,
  `select`, `socketpair` — translate this internally.
- **macOS carry-flag normalization.** BSD syscalls report failure
  by setting the carry flag and returning a positive errno; Linux
  returns a negative errno directly in `rax`. Every wrapper
  normalizes to Linux's convention so callers see one shape on
  both platforms.

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

## Source layout

Each exported symbol lives in a same-named file (`socket.asm`
exports `socket`, `bind.asm` exports `bind`, and so on). The one
exception is `syscall.inc`, a shared header included by every
wrapper for the per-platform `SYS_*` numbers and the
`SYSCALL_NORM` / `SYSCALL_ARG4` macros described above.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`). Consumers of
  `libsock.a` typically also link `libasm.a` to print the bytes
  they receive.
- [`../../examples/20-shared-lib/`](../../examples/20-shared-lib/)
  — the example that first demonstrates linking against an
  external library.
