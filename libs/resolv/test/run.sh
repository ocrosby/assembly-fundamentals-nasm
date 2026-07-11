#!/usr/bin/env bash
# run.sh — smoke-test suite for libresolv.a.
#
# Runs three tests in sequence:
#
#   1. resolv-smoke — end-to-end DNS resolution against a Python
#      mock server (mock-dns.py). The server binds a UDP socket
#      on an ephemeral port, writes the port to a file, and
#      responds to three canned names (an A record, an
#      NXDOMAIN, and a SERVFAIL). The client asserts each maps
#      to the expected libresolv return code.
#   2. fail-smoke   — libresolv's own syscall wrapper's failure
#      branch (resolv_random with NULL buf → -EFAULT). All
#      other syscalls the resolver makes route through libsock,
#      whose fail-smoke already covers them.
#   3. c-smoke      — verify libresolv is linkable and callable
#      from a C toolchain via __asm__ labels.
#
# Requires: nasm, ld, cc, python3.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/resolv/test

case "$(uname -s)" in
    Darwin)
        nasm_fmt="-f macho64 -DMACOS"
        sdk="$(xcrun -sdk macosx --show-sdk-path)"
        ld_cmd=(ld -w -macos_version_min 11.0 -lSystem -syslibroot "$sdk")
        ;;
    *)
        nasm_fmt="-f elf64"
        ld_cmd=(ld)
        ;;
esac

# libresolv depends on libsock at link time (socket / sendto /
# recvfrom / setsockopt / close). List libresolv first so
# static-archive resolution pulls in its objects to satisfy
# resolv_a's undefined references before libsock's own objects
# get considered.
libs=(../libresolv.a ../../sock/libsock.a)

tmp="$(mktemp -d)"
srv=""
cleanup() {
    [ -n "$srv" ] && kill "$srv" 2>/dev/null || true
    rm -rf "$tmp" resolv-smoke resolv-smoke.o fail-smoke fail-smoke.o c-smoke
}
trap cleanup EXIT

fail_total=0

# ---------------------------------------------------------------
# resolv-smoke — needs the mock DNS server on a runtime port.
# ---------------------------------------------------------------
portfile="$tmp/port"
python3 mock-dns.py "$portfile" &
srv=$!

port=""
for _ in $(seq 1 100); do
    if [ -f "$portfile" ]; then
        port="$(cat "$portfile")"
        break
    fi
    sleep 0.05
done
if [ -z "$port" ]; then
    printf "FAIL: %-12s (mock did not publish a port within ~5s)\n" "resolv-smoke"
    fail_total=$((fail_total + 1))
else
    # shellcheck disable=SC2086
    nasm $nasm_fmt -DDNS_PORT="$port" resolv-smoke.asm -o resolv-smoke.o
    "${ld_cmd[@]}" resolv-smoke.o "${libs[@]}" -o resolv-smoke

    set +e
    r_out="$(./resolv-smoke 2>&1)"
    r_code=$?
    set -e

    wait "$srv" 2>/dev/null || true
    srv=""

    if [ "$r_code" -eq 0 ]; then
        printf "PASS: %-12s output=[%s]\n" "resolv-smoke" "$r_out"
    else
        printf "FAIL: %-12s exit=%d output=[%s]\n" "resolv-smoke" "$r_code" "$r_out"
        fail_total=$((fail_total + 1))
    fi
fi

# ---------------------------------------------------------------
# fail-smoke — standalone (no server, no libsock needed).
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt fail-smoke.asm -o fail-smoke.o
"${ld_cmd[@]}" fail-smoke.o ../libresolv.a -o fail-smoke

set +e
f_out="$(./fail-smoke 2>&1)"
f_code=$?
set -e

if [ "$f_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "fail-smoke" "$f_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "fail-smoke" "$f_code" "$f_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# c-smoke — cc against libresolv + libsock.
# ---------------------------------------------------------------
c_arch_flag=""
c_link_flag=""
if [ "$(uname -s)" = "Darwin" ]; then
    c_arch_flag="-arch x86_64"
    c_link_flag="-Wl,-w"
fi

# shellcheck disable=SC2086
cc $c_arch_flag $c_link_flag c-smoke.c ../libresolv.a ../../sock/libsock.a -o c-smoke 2>/dev/null

set +e
c_out="$(./c-smoke 2>&1)"
c_code=$?
set -e

if [ "$c_code" -eq 0 ] && [ "$c_out" = "PASS" ]; then
    printf "PASS: %-12s output=[%s]\n" "c-smoke" "$c_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "c-smoke" "$c_code" "$c_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
