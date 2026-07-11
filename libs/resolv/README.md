# libs/resolv/

DNS resolver primitives packaged as the static archive
`libresolv.a`. The archive builds a DNS query in the wire
format defined by
[RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html), sends
it to a caller-supplied resolver over UDP via
[`libsock`](../sock/), waits for the response with a bounded
timeout, and parses out the first A record.

Every routine is a direct syscall (through `libsock`) or pure
computation — no libc, no libSystem call, no allocation. Same
discipline as [`libsock`](../sock/) and [`libio`](../io/).

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Exported symbols

| Symbol                     | Arguments                                                     | Returns                                    |
| -------------------------- | ------------------------------------------------------------- | ------------------------------------------ |
| `resolv_a`                 | `name`, `resolver_ip`, `port`, `out_ip*`                      | `0` on success, negative errno on failure  |
| `resolv_encode_query`      | `name`, `id`, `out_buf*`                                      | wire length or negative errno              |
| `resolv_decode_response`   | `buf*`, `len`, `expected_id`, `out_ip*`                       | `0` on success, negative errno on failure  |
| `resolv_random`            | `buf*`, `len`                                                 | non-negative on success, negative errno on failure |

`resolv_a` is the entry point most callers use. The other three
are exposed so consumers that want to run the wire encode /
decode step against a non-standard transport (a bespoke TCP DNS
client, a captured pcap, an in-process fuzzer) can reach the
building blocks directly.

`resolver_ip` is a `u32` IPv4 already in **network byte order**:
`8.8.8.8` is `0x08080808`, `127.0.0.1` is `0x0100007F` under
the little-endian storage x86-64 uses. `port` is a host-order
`u16`; `resolv_a` performs the byte swap internally.

## Error mapping

Every failure path in `resolv_a` funnels into a negative errno
so callers can `if (rax < 0)` uniformly:

| Return             | Value      | Meaning                                                     |
| ------------------ | ---------- | ----------------------------------------------------------- |
| `-EINVAL`          | `-22`      | Malformed name (empty, empty label, label > 63 bytes)       |
| `-ENOENT`          | `-2`       | DNS `NXDOMAIN` — the name does not exist                    |
| `-EIO`             | `-5`       | DNS `SERVFAIL`, or any RCODE without a more specific map    |
| `-ENODATA`         | `-96` (macOS) / `-61` (Linux) | Well-formed response with no A/IN answer |
| `-EBADMSG`         | `-74`      | Response truncated, ID mismatch, bad compression pointer    |
| `-ETIMEDOUT`       | `-60` (macOS) / `-110` (Linux) | recvfrom timed out (5-second default) |
| any libsock errno  | (various)  | Underlying socket call failed; the wrapper's errno is passed through |

The 5-second receive timeout is currently a compile-time
constant in `resolv-a.asm`. Future work (v1.1) exposes it as a
`resolv_a_ex` overload or via `setsockopt` on a caller-owned fd.

## What is not here — yet

The v1 scope is deliberately narrow: A records only, one
resolver, one query, no retries. Callers pass the resolver IP
directly, which unblocks a follow-up `libresolv` v1.1 that will
read `/etc/resolv.conf` via `libio` and pick a resolver from
there. Also deferred:

- AAAA (IPv6) records — same wire pattern, another QTYPE
- CNAME chasing — follow-the-alias loop with a hop cap
- Multi-record responses — return more than the first A
- TCP fallback on the truncated (`TC=1`) response
- `/etc/hosts` fallback before hitting the network
- Search-domain iteration
- Query retry with backoff across multiple resolvers
- DNSSEC signature validation — would drag crypto into scope

Each of these is a real user story worth writing, but each is
also a chapter of NASM in its own right. Adding them speculatively
before an example consumes them would blow past the constructive
sequence discipline the examples in this repo follow.

## Calling convention notes

The [shared `libs/` conventions](../README.md) apply. `resolv_a`
takes four arguments so they map exactly to the SysV registers
`rdi` (name), `rsi` (resolver IP), `rdx` (port), `rcx` (out
buffer). No `SYSCALL_ARG4` is needed at the resolver's own
level — the argument shuffle happens inside libsock's wrappers
for the syscalls libresolv actually issues (`sendto`,
`recvfrom`, `setsockopt`).

`resolv_random` is the only new syscall wrapper libresolv adds
on top of libsock. It calls `getentropy` on macOS (syscall 500)
and `getrandom` on Linux (syscall 318, `flags = 0`) so callers
never touch `/dev/urandom` and never need `libio`'s file
primitives just to get 2 bytes of entropy for a query ID.

The two syscalls disagree on their success return: `getentropy`
returns `0` (it is all-or-nothing), while `getrandom` returns
the number of bytes delivered. `resolv_random` passes both
through unchanged, so portable callers use the standard
`if (rax < 0)` check for failure rather than `if (rax != 0)`,
which would misfire on Linux even when the call succeeded.

## Build

### macOS

```bash
make                                # produces libs/resolv/libresolv.a
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the object files into
`libresolv.a` with `ar rcs`.

### Linux

```bash
make                                # produces libs/resolv/libresolv.a
```

On Linux the same `make` assembles with `nasm -f elf64`.

## Linking against `libresolv.a`

In the consumer's `.asm`:

```nasm
extern resolv_a
```

`libresolv` calls into `libsock` for every network syscall, so
consumers list both archives on the link line — `libresolv`
first so its undefined references to `socket`, `sendto`,
`recvfrom`, `setsockopt`, and `close` pull in libsock's
objects:

```makefile
LIBRESOLV := ../../libs/resolv/libresolv.a
LIBSOCK   := ../../libs/sock/libsock.a

$(BIN): $(OBJ) $(LIBRESOLV) $(LIBSOCK)
	$(LD) $(OBJ) $(LIBRESOLV) $(LIBSOCK) -o $(BIN)
```

Building the consumer does not automatically build the archive;
run `make -C ../../libs/resolv` first (which itself calls
`make -C ../sock` to satisfy the transitive dependency).

## Test

```bash
make test                           # requires python3
```

`make test` builds `libresolv.a`, `libsock.a`, and `libasm.a`,
then runs three smoke tests via the harness in [`test/`](test/):

- [`resolv-smoke.asm`](test/resolv-smoke.asm) + `mock-dns.py` —
  end-to-end DNS. `mock-dns.py` binds a UDP socket on
  `127.0.0.1` (kernel-assigned ephemeral port), publishes the
  port to a file, and responds to three canned names: one
  succeeds with an A record for `203.0.113.42` (RFC 5737
  TEST-NET-3), one returns `NXDOMAIN`, one returns `SERVFAIL`.
  The assembly client asserts each maps to the expected
  `resolv_a` return code, plus a fifth sub-check that the
  empty name is rejected at the encode step (`-EINVAL`)
  without ever hitting the network.
- [`fail-smoke.asm`](test/fail-smoke.asm) — every libresolv-
  owned syscall wrapper's failure branch. `resolv_random` is
  the only fresh syscall the archive contributes; every other
  syscall the resolver makes goes through libsock's already-
  covered wrappers.
- [`c-smoke.c`](test/c-smoke.c) — verifies `libresolv.a` is
  linkable and callable from a C toolchain via `__asm__`
  labels. Encodes a small query, rejects an obviously-too-
  short buffer, and pulls two random bytes — all without
  touching the network.

On success the runner prints one line per test:

```text
PASS: resolv-smoke output=[PASS]
PASS: fail-smoke   output=[PASS]
PASS: c-smoke      output=[PASS]
```

Both platforms are exercised on CI.

## See also

- [`../sock/`](../sock/) — Berkeley sockets syscall wrappers.
  `libresolv` depends on this archive at link time.
- [`../io/`](../io/) — file syscalls. Currently unused by
  `libresolv`; v1.1 will read `/etc/resolv.conf` and
  `/etc/hosts` through it.
- [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html) —
  the DNS wire format `libresolv` implements.
