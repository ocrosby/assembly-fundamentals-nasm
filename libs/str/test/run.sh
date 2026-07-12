#!/usr/bin/env bash
# run.sh — smoke-test suite for libstr.a.
#
# Runs the str-smoke harness and prints one PASS/FAIL line.
# Exits 0 iff every sub-check passed.
#
#   1. str-smoke — memcpy, memset, memcmp, strlen, strcmp
#
# Requires: nasm, ld (binutils). Assumes ../libstr.a and
# ../../asm/libasm.a already exist — the Makefile `test`
# target builds both first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/str/test

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

# libstr's smoke exercises panic on the .fail path, so libasm.a
# has to appear on the link line even when every sub-check passes
# — the linker only pulls objects for unresolved symbols, and
# panic is one of them.
libs=(../libstr.a ../../asm/libasm.a)

fail_total=0

# ---------------------------------------------------------------
# str-smoke — pure computation, no runtime state, no defines.
# ---------------------------------------------------------------
# shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
nasm $nasm_fmt str-smoke.asm -o str-smoke.o
"${ld_cmd[@]}" str-smoke.o "${libs[@]}" -o str-smoke

set +e
str_out="$(./str-smoke 2>&1)"
str_code=$?
set -e

if [ "$str_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "str-smoke" "$str_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "str-smoke" "$str_code" "$str_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
