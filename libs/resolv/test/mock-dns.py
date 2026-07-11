#!/usr/bin/env python3
"""Mock DNS server for libresolv's smoke test.

Binds a UDP socket on 127.0.0.1 to a kernel-assigned ephemeral
port, writes the chosen port atomically to the file named by
argv[1], and then serves at most a handful of DNS queries.

The mock responds according to the QNAME of each query:

  * "libresolv-ok.test"     → A record 203.0.113.42 (RCODE 0)
  * "libresolv-nxdomain.test" → NXDOMAIN response (RCODE 3)
  * anything else            → SERVFAIL (RCODE 2)

Only enough of RFC 1035 is implemented to satisfy the assembly
client — no compression on names, no additional records, no
truncation. Every socket call is timeout-bounded so a broken
client cannot hang CI. Exits 0 after five successful serves or
when the accept loop times out; the harness reads the exit
status via `wait`.
"""
from __future__ import annotations

import os
import socket
import struct
import sys

TIMEOUT_SECONDS = 10
MAX_SERVES = 5

OK_NAME = b"libresolv-ok.test"
NX_NAME = b"libresolv-nxdomain.test"
OK_ADDR = bytes((203, 0, 113, 42))          # TEST-NET-3 (RFC 5737)


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


def build_response(query: bytes) -> bytes | None:
    """Build the response corresponding to `query`. Return None on parse error."""
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
    if qtype != 1 or qclass != 1:
        # We only serve A/IN; call it SERVFAIL.
        return _servfail(query_id, query, next_off + 4)

    if qname == OK_NAME:
        return _answer(query_id, query, next_off + 4)
    if qname == NX_NAME:
        return _nxdomain(query_id, query, next_off + 4)
    return _servfail(query_id, query, next_off + 4)


def _flags(rcode: int) -> int:
    # QR=1 (response), Opcode=0 (query), AA=0, TC=0, RD=1, RA=1, Z=0, RCODE
    return 0x8180 | rcode


def _header(query_id: int, rcode: int, ancount: int) -> bytes:
    return struct.pack(">HHHHHH", query_id, _flags(rcode), 1, ancount, 0, 0)


def _echo_question(query: bytes, question_end: int) -> bytes:
    return query[12:question_end]


def _answer(query_id: int, query: bytes, question_end: int) -> bytes:
    header = _header(query_id, 0, 1)
    question = _echo_question(query, question_end)
    # Answer: name pointer back to the question (offset 12 in the packet),
    # TYPE=A, CLASS=IN, TTL=60, RDLENGTH=4, RDATA=OK_ADDR.
    answer = struct.pack(">HHHIH", 0xC00C, 1, 1, 60, 4) + OK_ADDR
    return header + question + answer


def _nxdomain(query_id: int, query: bytes, question_end: int) -> bytes:
    return _header(query_id, 3, 0) + _echo_question(query, question_end)


def _servfail(query_id: int, query: bytes, question_end: int) -> bytes:
    return _header(query_id, 2, 0) + _echo_question(query, question_end)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: mock-dns.py <port-file>", file=sys.stderr)
        return 2
    port_file = sys.argv[1]

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    sock.settimeout(TIMEOUT_SECONDS)
    port = sock.getsockname()[1]

    tmp = port_file + ".tmp"
    with open(tmp, "w") as f:
        f.write(str(port))
    os.replace(tmp, port_file)

    served = 0
    while served < MAX_SERVES:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            break
        response = build_response(data)
        if response is None:
            continue
        sock.sendto(response, addr)
        served += 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
