# DNS resolution

The [`libresolv`](../libs/resolv/) archive builds a DNS query
in the wire format defined by
[RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html),
sends it to a caller-supplied resolver over UDP via
[`libsock`](../libs/sock/), waits for the response with a
bounded timeout, transparently retries over TCP when the
response has the truncation (`TC=1`) bit set, and parses the
answer section into a caller-supplied buffer. Direct
syscalls only — no libc, no libSystem, no allocation.

## Three lookup layers

libresolv organizes its exports as three concentric layers.
Callers pick the layer that matches how much of the
resolver dance they want to own.

| Layer      | Entry point                              | What it does                                                                 |
| ---------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| Wire       | `resolv_random`, wire encode/decode      | Build / parse the raw DNS message. For consumers writing their own resolver. |
| Transport  | `resolv_a`, `resolv_aaaa`, `resolv_a_all`| Send + receive against one resolver. Handles UDP/TCP truncation retry.       |
| Hostname   | `resolv_hostname_at`, `resolv_hosts_lookup` | Walks `/etc/hosts` and `/etc/resolv.conf`. Handles search paths.          |

Each higher layer sits on the ones below it. `resolv_a`
calls the wire encoder; `resolv_hostname_at` calls
`resolv_a` for each resolver listed in `/etc/resolv.conf`.

## The wire format at a glance

A DNS message is a 12-byte header followed by variable-
length sections. libresolv builds queries with:

- **ID** — a random 16-bit token. `resolv_random` provides
  one via `/dev/urandom`; the response must echo it back or
  the wrapper treats it as spoofed.
- **QDCOUNT = 1** — one question section (one hostname to
  look up).
- **RD flag** — recursion desired. Set for every
  caller-facing query so the resolver walks the delegation
  chain itself.

The response's answer section is what the transport-layer
wrappers parse. `resolv_a` writes 4 wire-order bytes; the
`_all` variant writes a packed list.

## UDP → TCP truncation retry

DNS messages larger than 512 bytes (or 4096 with EDNS0, not
used here) are answered over UDP with only the truncated
head plus the `TC=1` bit in the flags. libresolv detects
this transparently, drops the UDP socket, opens a fresh TCP
socket to the same resolver on port 53, and retries. Callers
never see the retry; they just see the fully-parsed answer.

## The hostname layer and `/etc/resolv.conf`

`resolv_hostname_at` walks `/etc/resolv.conf` for a list of
`nameserver` entries and dispatches `resolv_a` against each
one in turn. If the name is unqualified (no dots), it also
retries with each `search` / `domain` directive appended.
The first successful lookup wins.

`resolv_hosts_lookup` short-circuits before the resolver
dance entirely — many hostnames (starting with `localhost`)
resolve locally without touching a nameserver. libresolv
mirrors the POSIX `getaddrinfo` behavior of consulting
`/etc/hosts` first.

## Composed helpers

- `resolv_sockaddr(name, resolver, port, out_sockaddr)` —
  resolve `name` to an IPv4 address and fill a
  `struct sockaddr_in` at `out_sockaddr` with the address
  and port ready to hand to `connect`.
- `resolv_dial(name, resolver, port)` — like
  `resolv_sockaddr` but goes all the way to a connected fd.
  Returns the fd or `-errno`.

Both save the caller from writing "resolve, then build a
sockaddr, then connect" — a pattern that shows up in
every network client.

## See also

- [`libs/resolv/`](../libs/resolv/) — the full archive.
- [`27-libraries.md`](27-libraries.md) — the archive
  index this chapter is a companion to.
- [`32-sock.md`](32-sock.md) — the socket layer libresolv
  sits on top of.
- [`examples/44-dns-lookup`](../examples/44-dns-lookup/) —
  the runnable that exercises `resolv_hosts_lookup`.

## Next

- Back to [docs/README.md](README.md).
