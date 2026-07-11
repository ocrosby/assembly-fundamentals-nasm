#!/usr/bin/env python3
"""Mock DNS server for libresolv's smoke test.

Binds both UDP and TCP on 127.0.0.1 to the same kernel-assigned
ephemeral port, writes the chosen port atomically to the file
named by argv[1], and serves at most a handful of DNS queries
via a select-multiplexed loop.

The mock responds according to the QNAME of each query:

  * "libresolv-ok.test"        → A record 203.0.113.42 (RCODE 0)
  * "libresolv-nxdomain.test"  → NXDOMAIN (RCODE 3)
  * "libresolv-servfail.test"  → SERVFAIL (RCODE 2)
  * "libresolv-truncated.test" → UDP: TC=1, empty answer
                                  TCP: full A record 203.0.113.42
  * anything else              → NXDOMAIN (RCODE 3)

Unknown names default to NXDOMAIN so the v1.5 search-domain
fallback in resolv_hostname_at can trigger — that path only
retries with a suffix when the first query returns NXDOMAIN.
Explicit SERVFAIL testing goes through libresolv-servfail.test.

The v1.6 truncation path lives inside libresolv-truncated.test:
the UDP response has the header's TC bit set and no answers,
forcing resolv_query to re-issue the same query over TCP. The
mock's TCP handler answers the retry with the real record.

Only enough of RFC 1035 is implemented to satisfy the assembly
client — no compression on names, no additional records. Every
socket call is timeout-bounded so a broken client cannot hang
CI. Exits 0 after MAX_SERVES successful serves or when the
select loop times out; the harness reads the exit status via
`wait`.
"""
from __future__ import annotations

import os
import select
import socket
import struct
import sys

TIMEOUT_SECONDS = 30
MAX_SERVES = 20

OK_NAME = b"libresolv-ok.test"
NX_NAME = b"libresolv-nxdomain.test"
SERVFAIL_NAME = b"libresolv-servfail.test"
AAAA_NAME = b"libresolv-aaaa.test"
CNAME_NAME = b"libresolv-cname.test"
MULTI_NAME = b"libresolv-multi.test"
LOOP_NAME = b"libresolv-loop-a.test"       # → loop-b.test → loop-a.test
LOOP_NAME_B = b"libresolv-loop-b.test"
TRUNC_NAME = b"libresolv-truncated.test"

OK_ADDR = bytes((203, 0, 113, 42))         # TEST-NET-3 (RFC 5737)
MULTI_ADDRS = [
    bytes((203, 0, 113, 1)),
    bytes((203, 0, 113, 2)),
    bytes((203, 0, 113, 3)),
]
AAAA_ADDR = bytes.fromhex("20010db8000000000000000000000042")  # 2001:db8::42


def decode_qname(payload: bytes, offset: int) -> tuple[bytes, int]:
    """Return (name-in-dotted-lowercase, offset-just-past-qname)."""
    parts: list[bytes] = []
    while offset < len(payload):
        length = payload[offset]
        if length == 0:
            return b".".join(parts).lower(), offset + 1
        # Compression pointers are legal in responses; we never
        # send one, and a well-formed client will not either.
        if length >= 0xC0:
            raise ValueError("unexpected compression pointer in query")
        offset += 1
        parts.append(payload[offset : offset + length])
        offset += length
    raise ValueError("qname walked off the end of the packet")


def encode_qname(name: bytes) -> bytes:
    """Encode a dotted name back into DNS wire labels."""
    out = bytearray()
    for label in name.split(b"."):
        out.append(len(label))
        out.extend(label)
    out.append(0)
    return bytes(out)


def build_response(query: bytes, *, over_tcp: bool = False) -> bytes | None:
    """Build the response corresponding to `query`. Return None on parse error.

    `over_tcp` distinguishes UDP and TCP paths. Only libresolv-truncated.test
    behaves differently across the two — UDP gets TC=1, TCP gets the real record.
    """
    if len(query) < 12:
        return None
    (query_id, _flags, qdcount, _ancount, _nscount, _arcount) = struct.unpack(
        ">HHHHHH", query[:12]
    )
    if qdcount != 1:
        return None
    try:
        qname, next_off = decode_qname(query, 12)
    except ValueError:
        return None
    if next_off + 4 > len(query):
        return None
    qtype, qclass = struct.unpack(">HH", query[next_off : next_off + 4])
    if qclass != 1:
        return _servfail(query_id, query, next_off + 4)

    if qtype == 1:                               # A
        return _dispatch_a(qname, query_id, query, next_off + 4, over_tcp=over_tcp)
    if qtype == 28:                              # AAAA
        return _dispatch_aaaa(qname, query_id, query, next_off + 4)
    return _servfail(query_id, query, next_off + 4)


def _dispatch_a(qname, query_id, query, qend, *, over_tcp=False):
    if qname == OK_NAME:
        return _answer_a(query_id, query, qend, [OK_ADDR])
    if qname == NX_NAME:
        return _nxdomain(query_id, query, qend)
    if qname == SERVFAIL_NAME:
        return _servfail(query_id, query, qend)
    if qname == MULTI_NAME:
        return _answer_a(query_id, query, qend, MULTI_ADDRS)
    if qname == CNAME_NAME:
        return _answer_cname(query_id, query, qend, OK_NAME)
    if qname == LOOP_NAME:
        return _answer_cname(query_id, query, qend, LOOP_NAME_B)
    if qname == LOOP_NAME_B:
        return _answer_cname(query_id, query, qend, LOOP_NAME)
    if qname == TRUNC_NAME:
        # v1.6 truncation path: UDP answer is header-only with
        # TC=1 set and zero answers. The client must re-issue
        # the same query over TCP; that path returns the real
        # A record.
        if over_tcp:
            return _answer_a(query_id, query, qend, [OK_ADDR])
        return _truncated(query_id, query, qend)
    if qname == AAAA_NAME:
        # AAAA-only name: honest answer to A is empty (RCODE 0,
        # ANCOUNT 0).
        return _empty_ok(query_id, query, qend)
    # Unknown name — default NXDOMAIN so search-domain fallback
    # can trigger without ambiguity.
    return _nxdomain(query_id, query, qend)


def _dispatch_aaaa(qname, query_id, query, qend):
    if qname == AAAA_NAME:
        return _answer_aaaa(query_id, query, qend, [AAAA_ADDR])
    if qname == NX_NAME:
        return _nxdomain(query_id, query, qend)
    if qname == SERVFAIL_NAME:
        return _servfail(query_id, query, qend)
    if qname == CNAME_NAME:
        # For AAAA, chase to a name that has an AAAA so the test
        # can exercise the chase-then-answer path.
        return _answer_cname(query_id, query, qend, AAAA_NAME)
    # Unknown name → NXDOMAIN (parallel to the A path). Callers
    # that specifically want RCODE=0/ANCOUNT=0 use the "A on
    # an AAAA-only name" path via _dispatch_a for AAAA_NAME.
    return _nxdomain(query_id, query, qend)


def _flags(rcode: int) -> int:
    # QR=1 (response), Opcode=0 (query), AA=0, TC=0, RD=1, RA=1, Z=0, RCODE
    return 0x8180 | rcode


def _header(query_id: int, rcode: int, ancount: int) -> bytes:
    return struct.pack(">HHHHHH", query_id, _flags(rcode), 1, ancount, 0, 0)


def _echo_question(query: bytes, question_end: int) -> bytes:
    return query[12:question_end]


def _answer_a(query_id, query, question_end, addrs):
    header = _header(query_id, 0, len(addrs))
    question = _echo_question(query, question_end)
    rrs = b"".join(
        struct.pack(">HHHIH", 0xC00C, 1, 1, 60, 4) + addr for addr in addrs
    )
    return header + question + rrs


def _answer_aaaa(query_id, query, question_end, addrs):
    header = _header(query_id, 0, len(addrs))
    question = _echo_question(query, question_end)
    rrs = b"".join(
        struct.pack(">HHHIH", 0xC00C, 28, 1, 60, 16) + addr for addr in addrs
    )
    return header + question + rrs


def _answer_cname(query_id, query, question_end, target):
    """CNAME answer pointing the query name at `target`."""
    header = _header(query_id, 0, 1)
    question = _echo_question(query, question_end)
    target_wire = encode_qname(target)
    rr = struct.pack(">HHHIH", 0xC00C, 5, 1, 60, len(target_wire)) + target_wire
    return header + question + rr


def _empty_ok(query_id, query, question_end):
    """Well-formed response, RCODE=0, ANCOUNT=0."""
    return _header(query_id, 0, 0) + _echo_question(query, question_end)


def _nxdomain(query_id, query, question_end):
    return _header(query_id, 3, 0) + _echo_question(query, question_end)


def _servfail(query_id, query, question_end):
    return _header(query_id, 2, 0) + _echo_question(query, question_end)


def _truncated(query_id, query, question_end):
    """RCODE 0 with the TC (truncation) flag set — no answer bytes.

    Flags byte layout: QR(1) | Opcode(4) | AA(1) | TC(1) | RD(1).
    _flags(0) already includes QR=1 and RD=1; OR in 0x0200 to
    flip TC on. The value goes into the second u16 of the
    header via _flags-style construction.
    """
    flags = _flags(0) | 0x0200
    header = struct.pack(">HHHHHH", query_id, flags, 1, 0, 0, 0)
    return header + _echo_question(query, question_end)


def _handle_tcp(conn: socket.socket) -> bool:
    """Serve exactly one DNS query on `conn`. Return True on success."""
    conn.settimeout(TIMEOUT_SECONDS)
    try:
        prefix = _recv_exact(conn, 2)
        if prefix is None:
            return False
        (length,) = struct.unpack(">H", prefix)
        payload = _recv_exact(conn, length)
        if payload is None:
            return False
        response = build_response(payload, over_tcp=True)
        if response is None:
            return False
        conn.sendall(struct.pack(">H", len(response)) + response)
        return True
    finally:
        conn.close()


def _recv_exact(conn: socket.socket, n: int) -> bytes | None:
    """Read exactly n bytes from conn, or return None on short read."""
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            return None
        buf.extend(chunk)
    return bytes(buf)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: mock-dns.py <port-file>", file=sys.stderr)
        return 2
    port_file = sys.argv[1]

    # Bind UDP first to claim an ephemeral port, then use the
    # same port for TCP. SO_REUSEADDR keeps macOS happy about
    # the double-bind after the previous run's socket may still
    # be in TIME_WAIT.
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("127.0.0.1", 0))
    port = udp.getsockname()[1]

    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp.bind(("127.0.0.1", port))
    tcp.listen(1)

    tmp = port_file + ".tmp"
    with open(tmp, "w") as f:
        f.write(str(port))
    os.replace(tmp, port_file)

    served = 0
    while served < MAX_SERVES:
        readable, _, _ = select.select([udp, tcp], [], [], TIMEOUT_SECONDS)
        if not readable:
            break
        for sock in readable:
            if sock is udp:
                data, addr = udp.recvfrom(4096)
                response = build_response(data)
                if response is None:
                    continue
                udp.sendto(response, addr)
                served += 1
            else:
                conn, _ = tcp.accept()
                if _handle_tcp(conn):
                    served += 1
            if served >= MAX_SERVES:
                break

    udp.close()
    tcp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
