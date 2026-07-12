#!/usr/bin/env bash
# run.sh — smoke-test suite for libsig.a.
#
# Runs one test and prints a PASS/FAIL line. Exits 0 iff every
# sub-check inside sig-smoke passed.
#
#   1. sig-smoke — sigprocmask round-trip (set + read back +
#                  unblock + read back), sigpending success
#                  return, and a bogus-how error normalization.
#
# Requires: nasm, ld (binutils). Assumes ../libsig.a and
# ../../asm/libasm.a already exist — the Makefile `test`
# target builds both first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/sig/test

# --- platform-specific toolchain (mirrors examples/01-exit-zero) ---
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

# libsig has libasm as a co-dep for panic in .fail. The linker
# only pulls in objects for unresolved symbols, so libasm.a is
# effectively free on the happy path.
libs=(../libsig.a ../../asm/libasm.a)

fail_total=0

# ---------------------------------------------------------------
# sig-smoke — needs the shared syscall.inc for SIG_* and
# SIG*ET_BYTES.
# ---------------------------------------------------------------
# shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
nasm $nasm_fmt -I ../.. -I../syscall/ sig-smoke.asm -o sig-smoke.o
"${ld_cmd[@]}" sig-smoke.o "${libs[@]}" -o sig-smoke

set +e
sig_out="$(./sig-smoke 2>&1)"
sig_code=$?
set -e

if [ "$sig_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "sig-smoke" "$sig_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "sig-smoke" "$sig_code" "$sig_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
