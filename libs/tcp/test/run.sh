#!/usr/bin/env bash
# run.sh — end-to-end smoke test for libtcp.a.
#
# Starts the loopback server, waits for it to publish its port,
# assembles and links tcp-smoke.asm against libtcp.a + libasm.a for
# the host platform, runs it, and asserts the reply. Prints PASS and
# exits 0 on success; prints a FAIL diagnostic and exits 1 otherwise.
#
# Requires: nasm, ld (binutils), python3. Assumes ../libtcp.a and
# ../../asm/libasm.a already exist (the Makefile `test` target builds
# them first).
set -euo pipefail

cd "$(dirname "$0")"                 # libs/tcp/test

tmp="$(mktemp -d)"
portfile="$tmp/port"
srv=""

cleanup() {
    [ -n "$srv" ] && kill "$srv" 2>/dev/null || true
    rm -rf "$tmp" tcp-smoke tcp-smoke.o
}
trap cleanup EXIT

# --- platform-specific toolchain (mirrors examples/01-exit-zero) ---
case "$(uname -s)" in
    Darwin)
        nasm_fmt="-f macho64 -DMACOS"
        sdk="$(xcrun -sdk macosx --show-sdk-path)"
        # -w silences a benign ld warning about the missing LC_BUILD_VERSION.
        ld_cmd=(ld -w -macos_version_min 11.0 -lSystem -syslibroot "$sdk")
        ;;
    *)
        nasm_fmt="-f elf64"
        ld_cmd=(ld)
        ;;
esac

# --- start the server; it writes the port file after listen() ---
python3 server.py "$portfile" &
srv=$!

# --- wait (bounded) for the port file to appear ---
port=""
for _ in $(seq 1 100); do
    if [ -f "$portfile" ]; then
        port="$(cat "$portfile")"
        break
    fi
    sleep 0.05
done
if [ -z "$port" ]; then
    echo "FAIL: server did not publish a port within ~5s"
    exit 1
fi

# --- assemble, link, run the client ---
# shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
nasm $nasm_fmt -DPORT="$port" tcp-smoke.asm -o tcp-smoke.o
"${ld_cmd[@]}" tcp-smoke.o ../libtcp.a ../../asm/libasm.a -o tcp-smoke

set +e
out="$(./tcp-smoke)"
code=$?
set -e

wait "$srv" 2>/dev/null || true
srv=""

if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q "TCP-OK"; then
    echo "PASS: tcp smoke — received: $out"
    exit 0
fi
echo "FAIL: exit=$code output=[$out]"
exit 1
