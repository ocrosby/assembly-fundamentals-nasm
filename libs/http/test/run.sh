#!/usr/bin/env bash
# run.sh — smoke-test suite for libhttp.a.
#
# Runs one test:
#   1. smoke — http_parse_request_line coverage across happy
#              paths, partial-input EAGAIN, and every documented
#              malformed-input EINVAL case.
#
# Requires: nasm, ld (binutils). Assumes ../libhttp.a,
# ../../str/libstr.a, and ../../asm/libasm.a already exist —
# the Makefile `test` target builds them first.
set -euo pipefail

cd "$(dirname "$0")"                 # libs/http/test

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

# libhttp uses libstr's memchr; smoke uses libstr's memcmp for
# happy-path token comparisons. libasm joins the link line for
# the panic call in the .fail path.
libs=(../libhttp.a ../../str/libstr.a ../../asm/libasm.a)
fail_total=0

# shellcheck disable=SC2086
nasm $nasm_fmt -I ../ smoke.asm -o smoke.o
"${ld_cmd[@]}" smoke.o "${libs[@]}" -o smoke

set +e
smoke_out="$(./smoke 2>&1)"
smoke_code=$?
set -e

if [ "$smoke_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "smoke" "$smoke_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "smoke" "$smoke_code" "$smoke_out"
    fail_total=$((fail_total + 1))
fi

exit "$fail_total"
