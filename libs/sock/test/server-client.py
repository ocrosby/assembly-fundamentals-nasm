#!/usr/bin/env python3
"""TCP client driver for server-smoke.

Reads argv[1] as the port the assembly server (`server-smoke`)
published on stdout, connects to `127.0.0.1:port`, sends a
short request, drains the reply until the server does its
`shutdown(SHUT_WR)` (which shows up as EOF on our recv side),
and verifies the reply contains the `SERVER-OK` banner.

Exits 0 on success, 1 on any mismatch or timeout, 2 on
argument-parsing failure. Every blocking call is time-bounded
so a hung server can't hang CI.

The counterpart in this directory (`server.py`) is a *server*
used by the client-side `tcp-smoke` test — this file is the
inverse: a *client* used by the server-side `server-smoke` test.
"""
import socket
import sys

TIMEOUT_SECONDS = 10
BANNER = b"SERVER-OK"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: server-client.py <port>", file=sys.stderr)
        return 2
    try:
        port = int(sys.argv[1])
    except ValueError:
        print(f"server-client: bad port argument {sys.argv[1]!r}", file=sys.stderr)
        return 2

    try:
        with socket.create_connection(
            ("127.0.0.1", port), timeout=TIMEOUT_SECONDS
        ) as sock:
            sock.settimeout(TIMEOUT_SECONDS)
            sock.sendall(b"PING\n")

            reply = bytearray()
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break                # server did its SHUT_WR
                reply.extend(chunk)
    except (OSError, socket.timeout) as exc:
        print(f"server-client: {exc}", file=sys.stderr)
        return 1

    if BANNER in reply:
        return 0
    print(f"server-client: unexpected reply {bytes(reply)!r}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
