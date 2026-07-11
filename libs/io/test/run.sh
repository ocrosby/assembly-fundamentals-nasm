#!/usr/bin/env bash
# run.sh — smoke-test suite for libio.a.
#
# Runs three tests in sequence and prints one PASS/FAIL line per
# test. Exits 0 iff every test passed.
#
#   1. io-smoke    — open / openat / lseek / pread / pwrite on a
#                    real temporary file; verifies each wrapper's
#                    success path plus a two-write / two-read
#                    round-trip
#   2. fail-smoke  — every wrapper's failure branch (macOS
#                    SYSCALL_NORM's neg-rax path). Bogus paths and
#                    fd=999999 force each syscall to return
#                    -ENOENT or -EBADF
#   3. c-smoke     — verify libio.a is linkable and callable from
#                    a C toolchain, matching libs/sock/test/c-smoke.c
#
# Requires: nasm, ld (binutils), cc, mktemp. Assumes ../libio.a
# already exists — the Makefile `test` target builds it first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/io/test

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

# io-smoke and fail-smoke are standalone binaries; c-smoke uses cc.
# They all need libio.a. io-smoke also needs a runtime tmpfile.
libs=(../libio.a)

tmpfile="$(mktemp /tmp/libio-smoke.XXXXXX)"
# Reserve a distinct scratch DIR path — mktemp -d would create it,
# but sub-check H needs to CREATE it via mkdir, so we only pick
# the name here. If a previous run crashed with the dir still on
# disk, the trap below rm -rf's it.
dirpath="$(mktemp -d /tmp/libio-smoke.dir.XXXXXX)"
rmdir "$dirpath"                       # H recreates it
cleanup() {
    # io-smoke sub-check J unlinks tmpfile and H/I round-trip
    # dirpath — best-effort clean here in case anything failed
    # mid-flight.
    rm -f "$tmpfile" \
          io-smoke io-smoke.o \
          fail-smoke fail-smoke.o \
          c-smoke /tmp/libio-c-smoke.tmp
    rm -rf "$dirpath"
}
trap cleanup EXIT

fail_total=0

# ---------------------------------------------------------------
# io-smoke — needs the mktemp'd path via -DTMPFILE.
# ---------------------------------------------------------------
# shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
# -I syscall/ so the smoke test can %include the shared header
# to pick up STATBUF_SIZE / ST_SIZE_OFF for its fstat check.
nasm $nasm_fmt -I../syscall/ \
    -DTMPFILE="\"$tmpfile\"" \
    -DDIRPATH="\"$dirpath\"" \
    io-smoke.asm -o io-smoke.o
"${ld_cmd[@]}" io-smoke.o "${libs[@]}" -o io-smoke

set +e
io_out="$(./io-smoke 2>&1)"
io_code=$?
set -e

if [ "$io_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "io-smoke" "$io_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "io-smoke" "$io_code" "$io_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# fail-smoke — standalone, no runtime state.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt fail-smoke.asm -o fail-smoke.o
"${ld_cmd[@]}" fail-smoke.o "${libs[@]}" -o fail-smoke

set +e
fail_out="$(./fail-smoke 2>&1)"
fail_code=$?
set -e

if [ "$fail_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "fail-smoke" "$fail_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "fail-smoke" "$fail_code" "$fail_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# c-smoke — cc against libio.a. Force -arch x86_64 on Darwin so
# clang matches the archive built by nasm -f macho64.
# ---------------------------------------------------------------
c_arch_flag=""
c_link_flag=""
if [ "$(uname -s)" = "Darwin" ]; then
    c_arch_flag="-arch x86_64"
    c_link_flag="-Wl,-w"
fi

# shellcheck disable=SC2086
cc $c_arch_flag $c_link_flag c-smoke.c ../libio.a -o c-smoke 2>/dev/null

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
