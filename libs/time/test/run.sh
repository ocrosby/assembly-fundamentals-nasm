#!/usr/bin/env bash
# run.sh — smoke-test suite for libtime.a.
#
# Runs two tests in sequence and prints one PASS/FAIL line per
# test. Exits 0 iff every test passed.
#
#   1. time-smoke — gettimeofday round-trip: call twice, verify
#                   the returned struct timeval is plausible
#                   (post-2023 tv_sec, tv_usec in range) and
#                   non-decreasing between the two calls
#   2. c-smoke    — verify libtime.a is linkable and callable
#                   from a C toolchain; second-opinion check
#                   against libc's time(NULL)
#
# Requires: nasm, ld (binutils), cc. Assumes ../libtime.a
# already exists — the Makefile `test` target builds it first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/time/test

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

# libasm.a joins the link line for time-smoke's `panic` call in
# the .fail path. Inert on the happy path — the linker only
# pulls in objects for unresolved symbols.
libs=(../libtime.a ../../asm/libasm.a)
fail_total=0

# ---------------------------------------------------------------
# time-smoke — needs syscall.inc for TIMEVAL_SIZE and TV_*_OFF.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. -I../syscall/ time-smoke.asm -o time-smoke.o
"${ld_cmd[@]}" time-smoke.o "${libs[@]}" -o time-smoke

set +e
time_out="$(./time-smoke 2>&1)"
time_code=$?
set -e

if [ "$time_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "time-smoke" "$time_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "time-smoke" "$time_code" "$time_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# c-smoke — cc against libtime.a. Force -arch x86_64 on Darwin
# so clang matches the archive built by nasm -f macho64.
# ---------------------------------------------------------------
c_arch_flag=""
c_link_flag=""
if [ "$(uname -s)" = "Darwin" ]; then
    c_arch_flag="-arch x86_64"
    c_link_flag="-Wl,-w"
fi

# shellcheck disable=SC2086
cc $c_arch_flag $c_link_flag c-smoke.c ../libtime.a -o c-smoke 2>/dev/null

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
