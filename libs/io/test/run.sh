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
# They all need libio.a. libasm.a is on the line for the sub-set of
# smokes that call into libasm's `panic` (v1.1) via their `.fail`
# path — inert for the ones that still hand-roll the write+exit
# sequence, since the linker only pulls in objects referenced by an
# unresolved symbol. io-smoke also needs a runtime tmpfile.
libs=(../libio.a ../../asm/libasm.a)

tmpfile="$(mktemp /tmp/libio-smoke.XXXXXX)"
# Reserve a distinct scratch DIR path — mktemp -d would create it,
# but sub-check H needs to CREATE it via mkdir, so we only pick
# the name here. If a previous run crashed with the dir still on
# disk, the trap below rm -rf's it.
dirpath="$(mktemp -d /tmp/libio-smoke.dir.XXXXXX)"
rmdir "$dirpath"                       # H recreates it
# Same dance for RENAMED_PATH: mktemp reserves a name that we
# then remove — sub-check K needs the destination to be absent
# so the rename creates a fresh entry rather than replacing.
renamed_path="$(mktemp -u /tmp/libio-smoke.renamed.XXXXXX)"
tmpfile_v13="$(mktemp -u /tmp/libio-smoke.v13.XXXXXX)"
symlink_path="$(mktemp -u /tmp/libio-smoke.symlink.XXXXXX)"
# v1.4: ITER_DIR is created + pre-populated with three flat
# regular files so the smoke test's iterator counts exactly 5
# entries (".", "..", "a", "b", "c").
iter_dir="$(mktemp -d /tmp/libio-smoke.iter.XXXXXX)"
: > "$iter_dir/a"
: > "$iter_dir/b"
: > "$iter_dir/c"
# v1.5: AT_DIR is created empty here; the smoke test opens it,
# populates it via the *at() family, then unlinks the contents
# and closes the dirfd. Any leftover on failure is caught by
# the trap's rm -rf.
at_dir="$(mktemp -d /tmp/libio-smoke.at.XXXXXX)"
cleanup() {
    # Sub-checks in io-smoke unlink each of the paths above on
    # the happy path (N: renamed_path, b: symlink_path, c:
    # tmpfile_v13). Best-effort clean here catches whatever an
    # intermediate failure left behind.
    rm -f "$tmpfile" "$renamed_path" "$tmpfile_v13" "$symlink_path" \
          io-smoke io-smoke.o \
          fail-smoke fail-smoke.o \
          fdgraph-smoke fdgraph-smoke.o \
          fcntl-smoke fcntl-smoke.o \
          file-copy-smoke file-copy-smoke.o \
          c-smoke /tmp/libio-c-smoke.tmp /tmp/libio-c-smoke.tmp2 \
                  /tmp/libio-c-smoke.link
    rm -rf "$dirpath" "$iter_dir" "$at_dir" \
           /tmp/libio-c-smoke.iter /tmp/libio-c-smoke.at
}
trap cleanup EXIT

fail_total=0

# ---------------------------------------------------------------
# io-smoke — needs the mktemp'd path via -DTMPFILE.
# ---------------------------------------------------------------
# shellcheck disable=SC2086  # nasm_fmt is intentionally word-split
# -I syscall/ so the smoke test can %include the shared header
# to pick up STATBUF_SIZE / ST_SIZE_OFF for its fstat check.
nasm $nasm_fmt -I ../.. -I../syscall/ \
    -DTMPFILE="\"$tmpfile\"" \
    -DDIRPATH="\"$dirpath\"" \
    -DRENAMED_PATH="\"$renamed_path\"" \
    -DTMPFILE_V13="\"$tmpfile_v13\"" \
    -DSYMLINK_PATH="\"$symlink_path\"" \
    -DITER_DIR="\"$iter_dir\"" \
    -DAT_DIR="\"$at_dir\"" \
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
nasm $nasm_fmt -I ../.. fail-smoke.asm -o fail-smoke.o
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
# fdgraph-smoke — v1.7 dup / dup2 / pipe.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. fdgraph-smoke.asm -o fdgraph-smoke.o
"${ld_cmd[@]}" fdgraph-smoke.o "${libs[@]}" -o fdgraph-smoke

set +e
fdg_out="$(./fdgraph-smoke 2>&1)"
fdg_code=$?
set -e

if [ "$fdg_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "fdgraph-smoke" "$fdg_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "fdgraph-smoke" "$fdg_code" "$fdg_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# fcntl-smoke — v1.8 fcntl + flock. Needs the shared syscall.inc
# for F_* / O_NONBLOCK / LOCK_* constants and its own mktemp'd
# lock file.
# ---------------------------------------------------------------
lockfile="$(mktemp -u /tmp/libio-fcntl-smoke.XXXXXX)"
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. -I../syscall/ \
    -DTMPFILE_LOCK="\"$lockfile\"" \
    fcntl-smoke.asm -o fcntl-smoke.o
"${ld_cmd[@]}" fcntl-smoke.o "${libs[@]}" -o fcntl-smoke

set +e
fcn_out="$(./fcntl-smoke 2>&1)"
fcn_code=$?
set -e
rm -f "$lockfile"

if [ "$fcn_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "fcntl-smoke" "$fcn_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "fcntl-smoke" "$fcn_code" "$fcn_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# mmap-smoke — v1.9 mmap + munmap. Needs the shared syscall.inc
# for PROT_* / MAP_* constants.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. -I../syscall/ mmap-smoke.asm -o mmap-smoke.o
"${ld_cmd[@]}" mmap-smoke.o "${libs[@]}" -o mmap-smoke

set +e
mmap_out="$(./mmap-smoke 2>&1)"
mmap_code=$?
set -e

if [ "$mmap_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "mmap-smoke" "$mmap_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "mmap-smoke" "$mmap_code" "$mmap_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# iov-smoke — v1.10 readv + writev. Uses libio's own pipe() to
# create a fixture and then send three 4-byte chunks via writev,
# receive them into two 6-byte iovecs via readv, and verify the
# split lines up. Needs the shared syscall.inc for IOVEC_SIZE
# and the IOV_*_OFF constants.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. -I../syscall/ iov-smoke.asm -o iov-smoke.o
"${ld_cmd[@]}" iov-smoke.o "${libs[@]}" -o iov-smoke

set +e
iov_out="$(./iov-smoke 2>&1)"
iov_code=$?
set -e

if [ "$iov_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "iov-smoke" "$iov_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "iov-smoke" "$iov_code" "$iov_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# file-copy-smoke — v1.11 file_copy composed helper. Needs three
# mktemp'd paths: a src (seeded with "HELLO WORLD!"), a dst that
# the helper creates, and an empty-src fixture for the zero-length
# short-circuit. Cleanup at the end wipes the empty-dst too.
# ---------------------------------------------------------------
fcp_src="$(mktemp -u /tmp/libio-file-copy-smoke.src.XXXXXX)"
fcp_dst="$(mktemp -u /tmp/libio-file-copy-smoke.dst.XXXXXX)"
fcp_empty_src="$(mktemp -u /tmp/libio-file-copy-smoke.esrc.XXXXXX)"
fcp_empty_dst="$(mktemp -u /tmp/libio-file-copy-smoke.edst.XXXXXX)"

# shellcheck disable=SC2086
nasm $nasm_fmt -I ../.. -I../syscall/ \
    -DSRC_PATH="\"$fcp_src\"" \
    -DDST_PATH="\"$fcp_dst\"" \
    -DEMPTY_SRC_PATH="\"$fcp_empty_src\"" \
    -DEMPTY_DST_PATH="\"$fcp_empty_dst\"" \
    file-copy-smoke.asm -o file-copy-smoke.o
"${ld_cmd[@]}" file-copy-smoke.o "${libs[@]}" -o file-copy-smoke

set +e
fcp_out="$(./file-copy-smoke 2>&1)"
fcp_code=$?
set -e
rm -f "$fcp_src" "$fcp_dst" "$fcp_empty_src" "$fcp_empty_dst"

if [ "$fcp_code" -eq 0 ]; then
    printf "PASS: %-12s output=[%s]\n" "file-copy-smoke" "$fcp_out"
else
    printf "FAIL: %-12s exit=%d output=[%s]\n" "file-copy-smoke" "$fcp_code" "$fcp_out"
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
