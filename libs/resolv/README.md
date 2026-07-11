# libs/resolv/

DNS resolver primitives packaged as the static archive
`libresolv.a`. The archive builds a DNS query in the wire
format defined by
[RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html), sends
it to a caller-supplied resolver over UDP via
[`libsock`](../sock/), waits for the response with a bounded
timeout, transparently retries over TCP when the response has
the truncation (`TC=1`) bit set, and parses the answer section
into either a single address (A or AAAA), a packed list of
addresses, or a CNAME target (chased transparently up to eight
hops). The [`libio`](../io/) archive is used for the
`/etc/hosts` and `/etc/resolv.conf` layer that the hostname-
level entry points sit on top of; both IPv4 and IPv6 variants
share the parser via a family flag. The hostname layer
iterates through every resolver listed in `/etc/resolv.conf`
and, for unqualified names, retries with each entry from the
`search` / `domain` directives.

Every routine is a direct syscall (through `libsock`) or pure
computation — no libc, no libSystem call, no allocation. Same
discipline as [`libsock`](../sock/) and [`libio`](../io/).

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Exported symbols

**v1.0 — DNS wire + UDP transport:**

| Symbol                     | Arguments                                                     | Returns                                    |
| -------------------------- | ------------------------------------------------------------- | ------------------------------------------ |
| `resolv_a`                 | `name`, `resolver_ip`, `port`, `out_ip*`                      | `0` on success, negative errno on failure  |
| `resolv_encode_query`      | `name`, `id`, `qtype`, `out_buf*`                             | wire length or negative errno              |
| `resolv_decode_records`    | `buf*`, `len`, `expected_id`, `qtype`, `out_buf*`, `max_count`| count copied (`>= 0`) or negative errno    |
| `resolv_decode_cname`      | `buf*`, `len`, `expected_id`, `out_name*`, `out_capacity`     | `0` on success, negative errno on failure  |
| `resolv_random`            | `buf*`, `len`                                                 | non-negative on success, negative errno on failure |

**v1.1 — /etc/hosts + /etc/resolv.conf integration:**

| Symbol                     | Arguments                                                              | Returns                                    |
| -------------------------- | ---------------------------------------------------------------------- | ------------------------------------------ |
| `resolv_hosts_lookup`      | `path`, `name`, `out_ip*`                                              | `0` on match, `-ENOENT` on miss, `-errno` on file error |
| `resolv_conf_read`         | `path`, `out_ip*`                                                      | `0` on success, `-ENOENT` if no nameserver, `-errno` on file error |
| `resolv_hostname_at`       | `hosts_path`, `conf_path`, `name`, `out_ip*`                           | `0` on success, negative errno on failure  |
| `resolv_hostname`          | `name`, `out_ip*`                                                      | `0` on success, negative errno on failure  |

**v1.2 — AAAA, CNAME chasing, and multi-record variants:**

| Symbol                     | Arguments                                                     | Returns                                    |
| -------------------------- | ------------------------------------------------------------- | ------------------------------------------ |
| `resolv_aaaa`              | `name`, `resolver_ip`, `port`, `out_ip16*`                    | `0` on success, negative errno on failure  |
| `resolv_a_all`             | `name`, `resolver_ip`, `port`, `out_buf*`, `max_count`        | count copied (`>= 1`) or negative errno    |
| `resolv_aaaa_all`          | `name`, `resolver_ip`, `port`, `out_buf*`, `max_count`        | count copied (`>= 1`) or negative errno    |
| `resolv_query`             | `name`, `resolver_ip`, `port`, `qtype`, `out_buf*`, `max_count` | count copied or negative errno           |

`resolv_a` continues to work exactly as before; v1.2 wires it
through the shared `resolv_query` workhorse under the hood, so
it now chases CNAMEs transparently up to eight hops. The hop
counter starts at 8 and returns `-ELOOP` (macOS `-62`,
Linux `-40`) when it hits zero, so a resolver that echoes an
infinite loop cannot lock the caller up.

`resolv_query` is the raw entry point — set `qtype` to any of
the values the decoder supports (`1` for A, `28` for AAAA) and
`max_count` to bound the copies. The wrappers above are thin
argument shuffles on top.

**v1.3 — IPv6-aware hosts + hostname entry points:**

| Symbol                     | Arguments                                                              | Returns                                    |
| -------------------------- | ---------------------------------------------------------------------- | ------------------------------------------ |
| `resolv_hosts_lookup6`     | `path`, `name`, `out_ip16*`                                            | `0` on match, `-ENOENT` on miss, `-errno` on file error |
| `resolv_hostname_at6`      | `hosts_path`, `conf_path`, `name`, `out_ip16*`                         | `0` on success, negative errno on failure  |
| `resolv_hostname6`         | `name`, `out_ip16*`                                                    | `0` on success, negative errno on failure  |

The v6 trio mirrors the v1.1 v4 trio. `resolv_hosts_lookup6`
parses the hosts file with `inet_pton6`, silently skipping
IPv4-only lines; the corresponding v4 entry silently skips
IPv6 lines. The two lookups share the parser via a single-byte
family flag spilled to the stack — bug fixes to the line
walker apply to both families without duplication.

`resolv_hostname_at6` / `resolv_hostname6` compose the v6
hosts lookup with the same `/etc/resolv.conf` reader used by
the v4 layer, then delegate to `resolv_aaaa`. The resolver
itself is still an IPv4 address; DNS-over-IPv6 transport is a
separate concern deferred past v1.3.

**v1.4 — multi-resolver failover + `:port` shorthand:**

| Symbol                     | Arguments                                                              | Returns                                    |
| -------------------------- | ---------------------------------------------------------------------- | ------------------------------------------ |
| `resolv_conf_read_all`     | `path`, `out_buf*`, `max_count`                                        | count copied (`0..max_count`) or negative errno |

**v1.5 — search-domain iteration:**

| Symbol                     | Arguments                                                              | Returns                                    |
| -------------------------- | ---------------------------------------------------------------------- | ------------------------------------------ |
| `resolv_conf_read_search`  | `path`, `out_buf*`, `capacity`                                         | count of domains, `0` when empty, `-ENOSPC` on overflow, `-errno` on file error |

`resolv_conf_read_search` parses the `search` and `domain`
directives from `/etc/resolv.conf` and writes each domain to
`out_buf` as a NUL-terminated ASCII string, laid down
back-to-back. Per RFC 1035, `search` and `domain` are
mutually exclusive — the LAST occurrence in the file wins.

`resolv_hostname_at` and `resolv_hostname_at6` now trigger a
search-domain fallback when the resolver list returns
`-ENOENT` for a name that contains no dot. For each search
suffix, the layer composes `<name>.<suffix>` into a stack
scratch buffer and retries the full resolver list. The first
composition that resolves wins; if every suffix fails, the
last errno is returned.

The fallback is deliberately narrow: names with a dot are
treated as already qualified (no suffix appended), and
non-`-ENOENT` errors (`-ETIMEDOUT`, `-ECONNREFUSED`, `-EIO`,
…) short-circuit without triggering search. This matches
libc's stub-resolver behavior — transient errors stop the
walk; NXDOMAIN keeps it going.

**v1.6 — TCP fallback on truncated (`TC=1`) responses:**

No new exported symbols; the fallback is transparent inside
`resolv_query`. When a UDP response comes back with the DNS
header's TC bit set — meaning the answer overflowed the
512-byte UDP limit — libresolv opens a TCP connection to the
same resolver, re-sends the same query with a 2-byte
big-endian length prefix (RFC 1035 §4.2.2), reads the length
prefix followed by the full response, and hands the result to
the same decoder path as the UDP flow.

The retry uses the same query ID that was sent over UDP, so
the decoder's ID check still holds. If the TCP retry itself
fails (connect refused, recv EOF before the full body arrives,
malformed length prefix), the errno is returned as if it were
a UDP error — the caller's resolver-list iterator moves on
to the next entry.

`resolv_conf_read_all` returns every parseable `nameserver`
directive packed into `out_buf` as consecutive 8-byte entries:

    offset 0..3  u32  IPv4 address (network byte order)
    offset 4..5  u16  port (host byte order — 53 by default,
                      or the value from a `nameserver
                      1.2.3.4:5353` shorthand)
    offset 6..7  u16  reserved (currently zero)

Zero return means the file was well-formed but held no
parseable directive — same signal as `resolv_conf_read`'s
`-ENOENT`, but the `_all` convention uses `0` for empty
because it is the natural fold of a count-return contract.

`resolv_hostname_at` and `resolv_hostname_at6` now enumerate
up to eight resolvers with `resolv_conf_read_all` and try
each in listed order, remembering the last failure. On the
first success the answer wins; if every resolver fails, the
LAST failure's errno is returned. The earlier ones are
discarded intentionally so callers see the most-recent
attempt's status rather than a cascade of errnos.

The `:port` shorthand is an intentional extension of the
resolv.conf format. Real system files never use it; libresolv
supports it so tests and scripted setups can point at
non-standard resolver ports (a mock server on an ephemeral
port, a stub resolver on `127.0.0.53:5353`, etc.) without a
separate configuration path. Malformed suffixes (port `0`,
port `> 65535`, non-digit characters) cause the WHOLE line
to be skipped — the parser never returns a partial entry.

`resolv_hostname` is the highest-level entry point for
production consumers — it composes the /etc/hosts lookup, the
/etc/resolv.conf parse, and `resolv_a` behind a two-argument
interface identical to `getaddrinfo`'s hostname-to-IPv4 case.
`resolv_hostname_at` exposes the same composition with
explicit paths so tests can point at fixtures without
depending on the real system files.

`resolv_a` remains available for consumers that want to bypass
the file layer entirely (embedded systems, sandboxed
processes without filesystem access, or callers that already
know the resolver IP). The other three v1.0 symbols are
exposed so consumers that want to run the wire encode /
decode step against a non-standard transport (a bespoke TCP
DNS client, a captured pcap, an in-process fuzzer) can reach
the building blocks directly.

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
| `-EBADMSG`         | `-74`      | ID mismatch, bad compression pointer, or (v1.6) TCP length prefix > 512 / short read |
| `-ELOOP`           | `-62` (macOS) / `-40` (Linux) | CNAME chain exceeded the 8-hop limit |
| `-ETIMEDOUT`       | `-60` (macOS) / `-110` (Linux) | recvfrom timed out (5-second default) |
| any libsock errno  | (various)  | Underlying socket call failed; the wrapper's errno is passed through |

The 5-second receive timeout is currently a compile-time
constant in `resolv-a.asm`. Future work (v1.1) exposes it as a
`resolv_a_ex` overload or via `setsockopt` on a caller-owned fd.

## What is not here — yet

v1.6 adds TCP fallback for truncated responses. Still deferred:

- DNS-over-IPv6 transport — the resolver IP itself is still a
  32-bit IPv4 address, even for AAAA queries
- `options ndots:N` — libresolv v1.5 uses a fixed rule
  ("no dot at all → search"), which matches the common case
  but not the RFC ndots knob
- Per-attempt retry with exponential backoff — currently the
  iterator makes one attempt per resolver
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

`make test` builds `libresolv.a`, `libsock.a`, `libio.a`, and
`libasm.a`, then runs eight smoke tests via the harness in
[`test/`](test/):

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
- [`v12-smoke.asm`](test/v12-smoke.asm) — exercises the v1.2
  additions against the same mock: AAAA success (single 16-byte
  answer), CNAME chase from `libresolv-cname.test` to the A
  record for `libresolv-ok.test`, hop-limit trip via a
  self-referential CNAME loop (`-ELOOP`), multi-record A with
  `resolv_a_all` (three records for `libresolv-multi.test`),
  and A on an AAAA-only name that comes back as `-ENODATA`.
- [`v16-smoke.asm`](test/v16-smoke.asm) — exercises the v1.6
  TCP fallback path. `libresolv-truncated.test` is a canned
  name whose UDP handler returns a header-only response with
  `TC=1`; libresolv must open a TCP connection to the same
  resolver, replay the query with a big-endian 2-byte length
  prefix, and stitch the untruncated answer together. The
  test asserts the final `ip` is populated with the real A
  record, and includes a UDP-only control case so a
  regression in the non-truncation path is also caught here.
- [`fail-smoke.asm`](test/fail-smoke.asm) — every libresolv-
  owned syscall wrapper's failure branch. `resolv_random` is
  the only fresh syscall the archive contributes; every other
  syscall the resolver makes goes through libsock's already-
  covered wrappers.
- [`hosts-smoke.asm`](test/hosts-smoke.asm) — exercises
  `resolv_hosts_lookup` and `resolv_hosts_lookup6` against a
  `mktemp`'d /etc/hosts fixture. Ten sub-checks: canonical
  name match, alias match, case-insensitive match, later-entry
  match, not-in-file miss, commented-out miss, non-IPv4-line
  skip (v4 lookup), non-existent-file error, v6 canonical
  match (`fe80::1`), and cross-family miss (v6 lookup of a
  v4-only name → `-ENOENT`).
- [`resolvconf-smoke.asm`](test/resolvconf-smoke.asm) —
  exercises `resolv_conf_read`, (v1.4) `resolv_conf_read_all`,
  and (v1.5) `resolv_conf_read_search` against `mktemp`'d
  /etc/resolv.conf fixtures. Nine sub-checks cover: first
  parseable `nameserver` wins, non-existent-file error,
  empty-file miss, count-of-two multi-entry parse, empty
  file returns `0` (not `-ENOENT`) under the count-return
  convention, `max_count` clamping, the `:port` shorthand
  (including malformed-port skipping), search-domain parse
  with last-write-wins between `domain` and `search`, and
  the bare-`domain` legacy shorthand.
- [`hostname-smoke.asm`](test/hostname-smoke.asm) —
  end-to-end test of `resolv_hostname_at` and
  `resolv_hostname_at6`. Six sub-checks: v4 hosts hit
  shortcuts DNS (no packet ever sent), v4 hosts miss falls
  through to DNS (which fails because the fixture points at a
  port nothing listens on — the point is that the fall-through
  *happens*), the same two paths for the v6 pair, (v1.4) a
  two-resolver failover where a dead entry at `127.0.0.1:1`
  is skipped and a live mock answers, and (v1.5) a
  search-domain fallback that composes the bare name
  `libresolv-ok` with the `test` suffix from the fixture's
  `search test` directive, then resolves via the mock.
- [`c-smoke.c`](test/c-smoke.c) — verifies `libresolv.a` is
  linkable and callable from a C toolchain via `__asm__`
  labels. Encodes a small query (both `QTYPE=A` and
  `QTYPE=AAAA`), rejects an obviously-too-short response,
  pulls a few random bytes, and reaches the v1.3 v6 hosts /
  hostname entry points with malformed paths to prove they
  respect the shared `-errno` convention. Nothing here
  touches the network.

On success the runner prints one line per test:

```text
PASS: resolv-smoke   output=[PASS]
PASS: v12-smoke      output=[PASS]
PASS: v16-smoke      output=[PASS]
PASS: hosts-smoke    output=[PASS]
PASS: resolvconf-smoke output=[PASS]
PASS: hostname-smoke output=[PASS]
PASS: fail-smoke     output=[PASS]
PASS: c-smoke        output=[PASS]
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
