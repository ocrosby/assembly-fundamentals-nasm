#!/usr/bin/env bash
# run.sh — smoke-test suite for libresolv.a.
#
# Runs six tests in sequence:
#
#   1. resolv-smoke     — end-to-end DNS against mock-dns.py
#      (v1.0 wire encode/decode, resolv_a orchestration)
#   2. hosts-smoke      — resolv_hosts_lookup against a mktemp'd
#      /etc/hosts fixture (v1.1)
#   3. resolvconf-smoke — resolv_conf_read against a mktemp'd
#      /etc/resolv.conf fixture (v1.1)
#   4. hostname-smoke   — resolv_hostname_at end-to-end: hosts
#      hit shortcuts DNS, hosts miss falls to the conf-derived
#      resolver (v1.1)
#   5. fail-smoke       — resolv_random failure branch
#   6. c-smoke          — verify libresolv is linkable and
#      callable from a C toolchain via __asm__ labels
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

# libresolv depends on libsock (socket / sendto / recvfrom /
# setsockopt / close / inet_pton4) and, from v1.1 onwards, on
# libio (open / pread) for the /etc/hosts and /etc/resolv.conf
# parsers. List libresolv first so static-archive resolution
# pulls its objects in to satisfy each undefined reference
# before libsock / libio get considered.
libs=(../libresolv.a ../../sock/libsock.a ../../io/libio.a)

tmp="$(mktemp -d)"
srv=""
cleanup() {
    [ -n "$srv" ] && kill "$srv" 2>/dev/null || true
    rm -rf "$tmp" \
        resolv-smoke resolv-smoke.o \
        hosts-smoke hosts-smoke.o \
        resolvconf-smoke resolvconf-smoke.o \
        hostname-smoke hostname-smoke.o \
        v12-smoke v12-smoke.o \
        v16-smoke v16-smoke.o \
        fail-smoke fail-smoke.o c-smoke
}
trap cleanup EXIT

fail_total=0

# --- create fixture files inside the sandboxed tmpdir ---
hosts_fixture="$tmp/hosts"
cat > "$hosts_fixture" <<'HOSTSEOF'
# test hosts file for libresolv v1.1
203.0.113.42 example.test example
fe80::1 ipv6-only.test
198.51.100.7 backup.test
# 192.0.2.1 comment.test
HOSTSEOF

conf_fixture="$tmp/resolv.conf"
cat > "$conf_fixture" <<'CONFEOF'
# test resolv.conf for libresolv v1.1
# nameserver 198.51.100.53
domain test
nameserver 192.0.2.53
nameserver 203.0.113.53
CONFEOF

conf_empty_fixture="$tmp/resolv.empty.conf"
cat > "$conf_empty_fixture" <<'EMPTYEOF'
# resolv.conf without any nameserver directive
domain test
options ndots:2
EMPTYEOF

# Ports fixture (v1.4). Two valid entries interleaved with
# three malformed :port lines — the parser must silently skip
# the malformed ones and keep the surrounding good entries.
conf_ports_fixture="$tmp/resolv.ports.conf"
cat > "$conf_ports_fixture" <<'PORTSEOF'
nameserver 127.0.0.1:5353
nameserver 10.0.0.1:0
nameserver 10.0.0.2:70000
nameserver 10.0.0.3:abc
nameserver 198.51.100.1:9999
PORTSEOF

# Search fixture (v1.5). `domain` comes first; `search` follows
# and, per last-write-wins, is what resolv_conf_read_search
# returns.
conf_search_fixture="$tmp/resolv.search.conf"
cat > "$conf_search_fixture" <<'SEARCHEOF'
domain first.example
search a.example b.example c.example
nameserver 127.0.0.1
SEARCHEOF

hostname_hosts_fixture="$tmp/hostname-hosts"
cat > "$hostname_hosts_fixture" <<'HNHEOF'
198.18.0.1 libresolv-hostname-hit.test
2001:db8::1 libresolv-hostname-v6.test
HNHEOF

# The hostname-smoke fixture points at 127.0.0.1 — a port
# nothing listens on, so the DNS fallback path times out /
# connection-refuses. That is what sub-check 2 asserts.
hostname_conf_fixture="$tmp/hostname-conf"
cat > "$hostname_conf_fixture" <<'HNCEOF'
nameserver 127.0.0.1
HNCEOF

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
# v12-smoke — needs its own mock instance (the previous one
# exits after resolv-smoke drains it) on a fresh ephemeral port.
# ---------------------------------------------------------------
portfile2="$tmp/port2"
python3 mock-dns.py "$portfile2" &
srv=$!

port2=""
for _ in $(seq 1 100); do
    if [ -f "$portfile2" ]; then
        port2="$(cat "$portfile2")"
        break
    fi
    sleep 0.05
done
if [ -z "$port2" ]; then
    printf "FAIL: %-12s (mock did not publish a port within ~5s)\n" "v12-smoke"
    fail_total=$((fail_total + 1))
else
    # shellcheck disable=SC2086
    nasm $nasm_fmt -DDNS_PORT="$port2" v12-smoke.asm -o v12-smoke.o
    "${ld_cmd[@]}" v12-smoke.o "${libs[@]}" -o v12-smoke

    set +e
    v12_out="$(./v12-smoke 2>&1)"
    v12_code=$?
    set -e

    wait "$srv" 2>/dev/null || true
    srv=""

    if [ "$v12_code" -eq 0 ]; then
        printf "PASS: %-12s output=[%s]\n" "v12-smoke" "$v12_out"
    else
        printf "FAIL: %-12s exit=%d output=[%s]\n" "v12-smoke" "$v12_code" "$v12_out"
        fail_total=$((fail_total + 1))
    fi
fi

# ---------------------------------------------------------------
# v16-smoke — TC=1 → TCP fallback. Needs its own mock on a
# fresh ephemeral port; the previous mocks have already exited.
# ---------------------------------------------------------------
portfile3="$tmp/port3v16"
python3 mock-dns.py "$portfile3" &
srv=$!

port3=""
for _ in $(seq 1 100); do
    if [ -f "$portfile3" ]; then
        port3="$(cat "$portfile3")"
        break
    fi
    sleep 0.05
done
if [ -z "$port3" ]; then
    printf "FAIL: %-12s (mock did not publish a port within ~5s)\n" "v16-smoke"
    fail_total=$((fail_total + 1))
else
    # shellcheck disable=SC2086
    nasm $nasm_fmt -DDNS_PORT="$port3" v16-smoke.asm -o v16-smoke.o
    "${ld_cmd[@]}" v16-smoke.o "${libs[@]}" -o v16-smoke

    set +e
    v16_out="$(./v16-smoke 2>&1)"
    v16_code=$?
    set -e

    wait "$srv" 2>/dev/null || true
    srv=""

    if [ "$v16_code" -eq 0 ]; then
        printf "PASS: %-12s output=[%s]\n" "v16-smoke" "$v16_out"
    else
        printf "FAIL: %-12s exit=%d output=[%s]\n" "v16-smoke" "$v16_code" "$v16_out"
        fail_total=$((fail_total + 1))
    fi
fi

# ---------------------------------------------------------------
# hosts-smoke — parses the /etc/hosts fixture. Standalone.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt -DHOSTS_PATH="\"$hosts_fixture\"" hosts-smoke.asm -o hosts-smoke.o
"${ld_cmd[@]}" hosts-smoke.o "${libs[@]}" -o hosts-smoke

set +e
h_out="$(./hosts-smoke 2>&1)"
h_code=$?
set -e

if [ "$h_code" -eq 0 ]; then
    printf "PASS: %-14s output=[%s]\n" "hosts-smoke" "$h_out"
else
    printf "FAIL: %-14s exit=%d output=[%s]\n" "hosts-smoke" "$h_code" "$h_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# resolvconf-smoke — parses the /etc/resolv.conf fixture.
# ---------------------------------------------------------------
# shellcheck disable=SC2086
nasm $nasm_fmt \
    -DCONF_PATH="\"$conf_fixture\"" \
    -DCONF_EMPTY_PATH="\"$conf_empty_fixture\"" \
    -DCONF_PORTS_PATH="\"$conf_ports_fixture\"" \
    -DCONF_SEARCH_PATH="\"$conf_search_fixture\"" \
    resolvconf-smoke.asm -o resolvconf-smoke.o
"${ld_cmd[@]}" resolvconf-smoke.o "${libs[@]}" -o resolvconf-smoke

set +e
rc_out="$(./resolvconf-smoke 2>&1)"
rc_code=$?
set -e

if [ "$rc_code" -eq 0 ]; then
    printf "PASS: %-14s output=[%s]\n" "resolvconf-smoke" "$rc_out"
else
    printf "FAIL: %-14s exit=%d output=[%s]\n" "resolvconf-smoke" "$rc_code" "$rc_out"
    fail_total=$((fail_total + 1))
fi

# ---------------------------------------------------------------
# hostname-smoke — composed hosts-then-DNS entry point.
#
# v1.4 sub-check 5 exercises multi-resolver failover: the
# fixture below lists a dead resolver first (127.0.0.1:1
# accepts no packets) and a live mock second. hostname-smoke
# only passes if the iteration actually falls through to the
# second resolver.
# ---------------------------------------------------------------
portfile3="$tmp/port3"
python3 mock-dns.py "$portfile3" &
srv=$!

port3=""
for _ in $(seq 1 100); do
    if [ -f "$portfile3" ]; then
        port3="$(cat "$portfile3")"
        break
    fi
    sleep 0.05
done

if [ -z "$port3" ]; then
    printf "FAIL: %-14s (mock did not publish a port within ~5s)\n" "hostname-smoke"
    fail_total=$((fail_total + 1))
else
    hostname_failover_conf="$tmp/hostname-failover-conf"
    cat > "$hostname_failover_conf" <<HFEOF
nameserver 127.0.0.1:1
nameserver 127.0.0.1:$port3
HFEOF

    # v1.5 search-domain fixture — one live resolver plus a
    # `search test` directive. Sub-check 6 sends "libresolv-ok"
    # (no dot), the mock NXDOMAINs it, then the fallback
    # composes "libresolv-ok.test" and the mock answers.
    hostname_search_conf="$tmp/hostname-search-conf"
    cat > "$hostname_search_conf" <<HSEOF
search test
nameserver 127.0.0.1:$port3
HSEOF

    # shellcheck disable=SC2086
    nasm $nasm_fmt \
        -DHOSTS_PATH="\"$hostname_hosts_fixture\"" \
        -DCONF_PATH="\"$hostname_conf_fixture\"" \
        -DFAILOVER_CONF_PATH="\"$hostname_failover_conf\"" \
        -DSEARCH_CONF_PATH="\"$hostname_search_conf\"" \
        hostname-smoke.asm -o hostname-smoke.o
    "${ld_cmd[@]}" hostname-smoke.o "${libs[@]}" -o hostname-smoke

    set +e
    hn_out="$(./hostname-smoke 2>&1)"
    hn_code=$?
    set -e

    wait "$srv" 2>/dev/null || true
    srv=""

    if [ "$hn_code" -eq 0 ]; then
        printf "PASS: %-14s output=[%s]\n" "hostname-smoke" "$hn_out"
    else
        printf "FAIL: %-14s exit=%d output=[%s]\n" "hostname-smoke" "$hn_code" "$hn_out"
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

# libresolv v1.3's C smoke references the /etc/hosts-backed
# entry points, which pull in libio (open/pread). Order the
# archives resolv → sock → io so undefined refs cascade.
# shellcheck disable=SC2086
cc $c_arch_flag $c_link_flag c-smoke.c \
    ../libresolv.a ../../sock/libsock.a ../../io/libio.a \
    -o c-smoke 2>/dev/null

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
