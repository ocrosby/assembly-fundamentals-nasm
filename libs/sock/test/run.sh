#!/usr/bin/env bash
# run.sh — smoke-test suite for libsock.a.
#
# Runs seven tests in sequence and prints one PASS/FAIL line per
# test. Exits 0 iff every test passed.
#
#   1. inet4-smoke   — byte-order helpers plus strict IPv4 text
#                      conversion (inet_pton4 / inet_ntop4)
#   2. inet6-smoke   — inet_pton6 / inet_ntop6 across all
#                      documented accept/reject cases and the RFC
#                      5952 canonical output rules
#   3. ipc-smoke     — socketpair, send/recv, sendto/recvfrom,
#                      sendmsg/recvmsg, select, poll — all
#                      exercised against an AF_UNIX SOCK_STREAM
#                      pair in the same process
#   4. fail-smoke    — every syscall wrapper's failure branch
#                      (macOS SYSCALL_NORM's neg-rax path);
#                      invalid fd / invalid AF / negative nfds
#                      force each wrapper to return a negative
#                      errno
#   5. tcp-smoke     — end-to-end TCP client against a loopback
#                      Python server (server.py)
#   6. server-smoke  — end-to-end TCP server; a Python client
#                      (server-client.py) drives the exchange
#   7. c-smoke       — verify libsock.a is linkable and callable
#                      from a C toolchain, not just from NASM
#
# Together these cover every one of the 30 symbols libsock.a
# exports at least once via a success path (1-3, 5, 6) and every
# syscall wrapper's failure branch once (4). Test 7 is a
# compatibility smoke — it doesn't add coverage but verifies the
# archive is usable from a C consumer that lists it before libc
# on the link line.
#
# Requires: nasm, ld (binutils), cc, python3. Assumes
# ../libsock.a and ../../asm/libasm.a already exist — the
# Makefile `test` target builds them first.
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
    nasm $nasm_fmt -I ../.. "${name}.asm" -o "${name}.o"
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
run_standalone ipc-smoke
run_standalone fail-smoke
run_standalone bind-listen-smoke
run_standalone client-connect-smoke
run_standalone socket-timeout-smoke

# ---------------------------------------------------------------
# tcp-smoke — Python server, assembly client, coordinate via port
# file that server.py writes atomically after listen().
# ---------------------------------------------------------------
tmp="$(mktemp -d)"
srv=""
srv_smoke=""

cleanup() {
    [ -n "$srv" ] && kill "$srv" 2>/dev/null || true
    [ -n "$srv_smoke" ] && kill "$srv_smoke" 2>/dev/null || true
    rm -rf "$tmp"
    rm -f tcp-smoke tcp-smoke.o server-smoke server-smoke.o
}
trap cleanup EXIT

portfile="$tmp/port"
python3 server.py "$portfile" &
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
    printf "FAIL: %-14s (server did not publish a port within ~5s)\n" "tcp-smoke"
    fail_total=$((fail_total + 1))
else
    # shellcheck disable=SC2086
    nasm $nasm_fmt -I ../.. -DPORT="$port" tcp-smoke.asm -o tcp-smoke.o
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
fi

# ---------------------------------------------------------------
# server-smoke — assembly server publishes port on stdout, Python
# client (server-client.py) drives the exchange.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. server-smoke.asm -o server-smoke.o
"${ld_cmd[@]}" server-smoke.o "${libs[@]}" -o server-smoke

srv_out="$tmp/server-out"
./server-smoke > "$srv_out" 2>&1 &
srv_smoke=$!

port=""
for _ in $(seq 1 100); do
    # `|| true` because under `set -e` a grep with no match would
    # abort the whole script — we deliberately poll until it hits.
    port=$(grep '^PORT:' "$srv_out" 2>/dev/null | head -1 | sed 's/^PORT://' || true)
    if [ -n "$port" ]; then
        break
    fi
    sleep 0.05
done

if [ -z "$port" ]; then
    printf "FAIL: %-14s (server did not publish a port within ~5s)\n" "server-smoke"
    kill "$srv_smoke" 2>/dev/null || true
    fail_total=$((fail_total + 1))
    exit "$fail_total"
fi

set +e
python3 server-client.py "$port"
client_code=$?
wait "$srv_smoke"
server_code=$?
set -e
srv_smoke=""

srv_msg="$(head -1 "$srv_out")"
if [ "$server_code" -eq 0 ] && [ "$client_code" -eq 0 ]; then
    printf "PASS: %-14s output=[%s]\n" "server-smoke" "$srv_msg"
else
    printf "FAIL: %-14s server_exit=%d client_exit=%d output=[%s]\n" \
        "server-smoke" "$server_code" "$client_code" "$srv_msg"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# c-smoke — verify libsock.a is callable from a C toolchain.
# ---------------------------------------------------------------
# On Darwin libsock.a is built as x86_64; force clang to match so
# an Apple Silicon runner (native arm64) picks up the archive's
# objects and runs the result under Rosetta 2. On Linux the
# native arch already matches. -Wl,-w silences the ld warnings
# about missing LC_BUILD_VERSION load commands NASM does not emit.
c_arch_flag=""
c_link_flag=""
if [ "$(uname -s)" = "Darwin" ]; then
    c_arch_flag="-arch x86_64"
    c_link_flag="-Wl,-w"
fi

# shellcheck disable=SC2086  # word-splitting the flag lists is intentional
cc $c_arch_flag $c_link_flag c-smoke.c ../libsock.a -o c-smoke 2>/dev/null

set +e
c_out="$(./c-smoke 2>&1)"
c_code=$?
set -e
rm -f c-smoke

if [ "$c_code" -eq 0 ] && [ "$c_out" = "PASS" ]; then
    printf "PASS: %-14s output=[%s]\n" "c-smoke" "$c_out"
else
    printf "FAIL: %-14s exit=%d output=[%s]\n" "c-smoke" "$c_code" "$c_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
