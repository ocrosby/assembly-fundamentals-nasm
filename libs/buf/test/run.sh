#!/usr/bin/env bash
# run.sh — smoke-test suite for libbuf.a.
#
# Runs one test:
#   1. buf-smoke — buf_init / append / reserve grow / reset /
#                  free round trip, plus double-free no-op.
#
# Requires: nasm, ld (binutils). Assumes ../libbuf.a,
# ../../io/libio.a, and ../../asm/libasm.a already exist —
# the Makefile `test` target builds them first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/buf/test

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

# libbuf composes libio (mmap/munmap). libasm joins the link
# line for the panic call in the .fail path.
libs=(../libbuf.a ../../io/libio.a ../../asm/libasm.a)
fail_total=0

# ---------------------------------------------------------------
# buf-smoke — needs buf.inc for BUF_SIZE and BUF_*_OFF.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../ buf-smoke.asm -o buf-smoke.o
"${ld_cmd[@]}" buf-smoke.o "${libs[@]}" -o buf-smoke

set +e
buf_out="$(./buf-smoke 2>&1)"
buf_code=$?
set -e

if [ "$buf_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "buf-smoke" "$buf_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "buf-smoke" "$buf_code" "$buf_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
