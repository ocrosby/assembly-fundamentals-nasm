#!/usr/bin/env bash
# run.sh — smoke-test suite for libproc.a.
#
# Runs two tests in sequence and prints one PASS/FAIL line per
# test. Exits 0 iff every test passed.
#
#   1. proc-smoke — fork() into child that _exit(42), parent
#                   verifies wait4(child) returns child pid
#                   with wstatus decoding to WEXITSTATUS=42,
#                   plus kill(reaped_pid, 0) returns -ESRCH.
#                   Covers all five v1.0 wrappers.
#   2. c-smoke    — verify libproc.a is linkable and callable
#                   from a C toolchain, using __asm__ labels
#                   to bypass Mach-O's underscore mangling.
#
# Requires: nasm, ld (binutils), cc. Assumes ../libproc.a
# already exists — the Makefile `test` target builds it first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/proc/test

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

libs=(../libproc.a)
fail_total=0

# ---------------------------------------------------------------
# proc-smoke — needs syscall.inc for WNOHANG-style constants.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I../syscall/ proc-smoke.asm -o proc-smoke.o
"${ld_cmd[@]}" proc-smoke.o "${libs[@]}" -o proc-smoke

set +e
proc_out="$(./proc-smoke 2>&1)"
proc_code=$?
set -e

if [ "$proc_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "proc-smoke" "$proc_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "proc-smoke" "$proc_code" "$proc_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# c-smoke — cc against libproc.a. Force -arch x86_64 on Darwin
# so clang matches the archive built by nasm -f macho64.
# ---------------------------------------------------------------
c_arch_flag=""
c_link_flag=""
if [ "$(uname -s)" = "Darwin" ]; then
    c_arch_flag="-arch x86_64"
    c_link_flag="-Wl,-w"
fi

# shellcheck disable=SC2086
cc $c_arch_flag $c_link_flag c-smoke.c ../libproc.a -o c-smoke 2>/dev/null

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
