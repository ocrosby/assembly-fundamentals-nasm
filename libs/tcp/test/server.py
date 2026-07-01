#!/usr/bin/env python3
"""Loopback TCP server for the libtcp.a smoke test.

Binds 127.0.0.1 on a kernel-assigned ephemeral port, publishes that
port atomically to the file named by argv[1], accepts one connection,
reads and discards the request, and replies with a known banner. The
port file is written with os.replace *after* listen(), so its
appearance is an unambiguous "ready, connect here" signal for run.sh
— no fixed port, no readiness race.

Every blocking call is timeout-bounded so a broken client can never
hang CI. Python 3 standard library only.
"""
import os
import socket
import sys

REPLY = b"TCP-OK\n"
TIMEOUT_SECONDS = 10


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: server.py <port-file>", file=sys.stderr)
        return 2
    port_file = sys.argv[1]

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(1)
    sock.settimeout(TIMEOUT_SECONDS)

    port = sock.getsockname()[1]
    tmp = port_file + ".tmp"
    with open(tmp, "w") as f:
        f.write(str(port))
    os.replace(tmp, port_file)  # atomic: file appears only once complete

    try:
        conn, _ = sock.accept()
    except socket.timeout:
        print("server: timed out waiting for a connection", file=sys.stderr)
        return 1
    with conn:
        conn.settimeout(TIMEOUT_SECONDS)
        conn.recv(1024)          # read the request; content is irrelevant
        conn.sendall(REPLY)
    return 0


if __name__ == "__main__":
    sys.exit(main())
