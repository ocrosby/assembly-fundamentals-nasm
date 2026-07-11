# libs/sock/inet/

Pure-computation helpers from POSIX
[`<arpa/inet.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/arpa_inet.h.html):
byte-order conversion and IPv4/IPv6 text-to-binary conversion.
Nothing in this directory enters the kernel; nothing here
depends on `../syscall/syscall.inc`.

For consumer-facing documentation of the archive as a whole
(build, link line, calling convention, TCP-client example) see
[`../README.md`](../README.md).

## Contents

### Byte order

Each of these converts a fixed-width unsigned integer between
host order (little-endian on x86-64) and network order
(big-endian). On any little-endian host the two directions of
each pair are byte-identical operations, but callers still get
the named routine so the call site documents intent.

| File          | Symbol   | Width  | Body                       |
| ------------- | -------- | ------ | -------------------------- |
| `htons.asm`   | `htons`  | 16-bit | `movzx eax, di; rol ax, 8` |
| `ntohs.asm`   | `ntohs`  | 16-bit | `movzx eax, di; rol ax, 8` |
| `htonl.asm`   | `htonl`  | 32-bit | `mov eax, edi; bswap eax`  |
| `ntohl.asm`   | `ntohl`  | 32-bit | `mov eax, edi; bswap eax`  |

Each routine is two instructions plus `ret`. No memory access,
no stack frame, no syscall.

### IPv4 text ↔ binary

| File               | Symbol         | Purpose                                              |
| ------------------ | -------------- | ---------------------------------------------------- |
| `inet-pton4.asm`   | `inet_pton4`   | Parse `"1.2.3.4"` → 4 bytes in network order.        |
| `inet-ntop4.asm`   | `inet_ntop4`   | Format a 4-byte address → dotted-decimal string.     |

`inet_pton4` is strict, matching POSIX `inet_pton(AF_INET, ...)`
and not the older `inet_aton()`. It rejects:

  * Leading zeros within an octet: `"01.2.3.4"` fails. This
    closes the historical trap where `inet_aton()` reads a
    leading `0` as octal (so `"0177"` becomes 127, not 177).
  * Out-of-range octets: `"1.2.3.256"` fails.
  * Missing octets: `"1.2.3"` fails.
  * Trailing garbage: `"1.2.3.4.5"` fails.

`inet_ntop4` requires the destination buffer to be at least
`INET_ADDRSTRLEN` (16 bytes) and returns `NULL` when it is not,
matching POSIX behavior for `ENOSPC`. On success it returns the
original `dst` pointer.

### IPv6 text ↔ binary

| File               | Symbol         | Purpose                                              |
| ------------------ | -------------- | ---------------------------------------------------- |
| `inet-pton6.asm`   | `inet_pton6`   | Parse RFC 4291 IPv6 text → 16 bytes in network order.|
| `inet-ntop6.asm`   | `inet_ntop6`   | Format 16 bytes → RFC 5952 canonical text.           |

`inet_pton6` supports the full RFC 4291 grammar:

  * One to eight hex groups of one to four case-insensitive
    digits (`AbCd::1` parses).
  * `::` compression, at most once per address, expanding to at
    least one zero group.
  * Leading `::` (`::1`), trailing `::` (`1::`), and the pure
    `::` (all zeros).
  * IPv4-mapped tail form: `::ffff:192.0.2.1`. The dotted-quad
    parser reuses the strict `inet_pton4` rules (leading zeros
    rejected, octet range checked).

It rejects the bare-IPv4 form (`1.2.3.4` with no `::` prefix),
scope IDs (`%eth0` — POSIX `inet_pton()` does not support these),
a leading single colon that is not part of `::`, a trailing
colon, more than four hex digits in a group, and a `::` that
would need to expand to zero groups (`1:2:3:4:5:6:7:8::`).

On failure it leaves `*dst` untouched: the parse writes into a
stack-local 8-group scratch buffer and only assembles the final
16 output bytes after every syntactic check has passed.

`inet_ntop6` emits RFC 5952 canonical form:

  * Lowercase hex, `'a'..'f'` (not `'A'..'F'`).
  * No leading zeros within a group (`0x00ab` becomes `"ab"`,
    `0x0000` becomes `"0"`).
  * Longest run of two or more consecutive zero groups
    compressed to `::`. When runs tie, the first wins (RFC 5952
    §4.2.3).
  * IPv4-mapped addresses (bytes 0..9 zero, bytes 10..11 `0xff`)
    printed as `::ffff:a.b.c.d`.

The destination buffer must be at least `INET6_ADDRSTRLEN` (46
bytes: `"ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255"` plus
NUL). Smaller buffers cause a `NULL` return; on success the
original `dst` is returned.

## Internal helpers

Two files carry file-local subroutines that are never exported:

- `inet-ntop4.asm` defines an `EMIT_BYTE` macro that expands
  once per octet, writing a `u8` as one, two, or three decimal
  digits. The macro uses `%%`-scoped local labels so per-octet
  expansions do not clash in the object file.
- `inet-ntop6.asm` uses three internal `call`/`ret` helpers:
  `.emit_group` writes a hex group with leading-zero
  suppression, `.hex_char` maps a nibble to a lowercase ASCII
  hex digit, and `.emit_byte` handles decimal-octet emission
  for the IPv4-mapped tail. All three are `.`-prefixed labels
  local to the source file.

Neither file exports its helpers; both are visible only within
their own compilation unit.

## Build

Files in this directory are self-contained — no shared header,
no include-path juggling. The parent [`../Makefile`](../Makefile)
compiles them with a plain `nasm $(NASM_FLAGS) $< -o $@` pattern
rule.
