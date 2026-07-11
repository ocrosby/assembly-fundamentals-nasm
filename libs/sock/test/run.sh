#!/usr/bin/env bash
# run.sh — smoke-test suite for libsock.a.
#
# Runs three tests in sequence and prints one PASS/FAIL line per
# test. Exits 0 iff every test passed.
#
#   1. inet4-smoke — byte-order helpers (htons/htonl/ntohs/ntohl)
#      and the strict IPv4 text conversion (inet_pton4/inet_ntop4)
#   2. inet6-smoke — inet_pton6/inet_ntop6 across 33 sub-checks
#      spanning the full RFC 4291 accepted grammar, the documented
#      rejection cases, RFC 5952 canonical output, and a round-trip
#   3. tcp-smoke   — end-to-end client against a loopback Python
#      server on an ephemeral kernel-assigned port
#
# Requires: nasm, ld (binutils), python3 (for tcp-smoke). Assumes
# ../libsock.a and ../../asm/libasm.a already exist — the Makefile
# `test` target builds them first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/sock/test

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

libs=(../libsock.a ../../asm/libasm.a)
fail_total=0

# ---------------------------------------------------------------
# Standalone tests — assemble, link, run, expect exit code 0.
# ---------------------------------------------------------------
run_standalone() {
    local name="$1"
    # shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
    nasm $nasm_fmt "${name}.asm" -o "${name}.o"
    "${ld_cmd[@]}" "${name}.o" "${libs[@]}" -o "${name}"

    set +e
    local out code
    out="$(./${name} 2>&1)"
    code=$?
    set -e
    rm -f "${name}.o" "${name}"

    if [ "$code" -eq 0 ]; then
        printf "PASS: %-14s output=[%s]\n" "$name" "$out"
    else
        printf "FAIL: %-14s exit=%d output=[%s]\n" "$name" "$code" "$out"
        fail_total=$((fail_total + 1))
    fi
}

run_standalone inet4-smoke
run_standalone inet6-smoke

# ---------------------------------------------------------------
# tcp-smoke — needs a loopback server + a runtime-assigned port.
# ---------------------------------------------------------------
tmp="$(mktemp -d)"
portfile="$tmp/port"
srv=""

cleanup_tcp() {
    [ -n "$srv" ] && kill "$srv" 2>/dev/null || true
    rm -rf "$tmp" tcp-smoke tcp-smoke.o
}
trap cleanup_tcp EXIT

# Start the server; it writes the port file after listen().
python3 server.py "$portfile" &
srv=$!

# Wait (bounded) for the port file to appear.
port=""
for _ in $(seq 1 100); do
    if [ -f "$portfile" ]; then
        port="$(cat "$portfile")"
        break
    fi
    sleep 0.05
done
if [ -z "$port" ]; then
    printf "FAIL: %-14s (server did not publish a port within ~5s)\n" "tcp-smoke"
    fail_total=$((fail_total + 1))
    exit "$fail_total"
fi

# shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
nasm $nasm_fmt -DPORT="$port" tcp-smoke.asm -o tcp-smoke.o
"${ld_cmd[@]}" tcp-smoke.o "${libs[@]}" -o tcp-smoke

set +e
tcp_out="$(./tcp-smoke)"
tcp_code=$?
set -e

wait "$srv" 2>/dev/null || true
srv=""

if [ "$tcp_code" -eq 0 ] && printf '%s' "$tcp_out" | grep -q "TCP-OK"; then
    printf "PASS: %-14s output=[%s]\n" "tcp-smoke" "$tcp_out"
else
    printf "FAIL: %-14s exit=%d output=[%s]\n" "tcp-smoke" "$tcp_code" "$tcp_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
