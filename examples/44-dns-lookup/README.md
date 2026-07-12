# 44 — dns-lookup

Look "localhost" up in `/etc/hosts` via libresolv's
`resolv_hosts_lookup`. Verifies the returned address is
`127.0.0.1` byte-for-byte and exits 42.

First runnable that uses libresolv. Purely hermetic — no
network, no DNS servers, no /etc dependencies beyond the
standard hosts file.

## Introduces

- **`resolv_hosts_lookup` (libresolv).** Reads an
  `/etc/hosts`-format file at `path`, walks the entries,
  writes the first matching address to `out_ip` as 4 wire-
  order bytes. `0` on success, negative errno on failure.
- **Wire-order addresses.** `127.0.0.1` on the wire is
  the byte sequence `127, 0, 0, 1` in that order — the
  most-significant octet first. The example compares against
  a `db 127, 0, 0, 1` reference to keep intent visible.

## Program flow

```
resolv_hosts_lookup("/etc/hosts", "localhost", &out_ip)
    → 0 on success; out_ip filled with 4 wire-order bytes
byte-compare out_ip against [127, 0, 0, 1]
exit(42)
```

## Why hosts and not DNS

libresolv also exports `resolv_a` (DNS A-record lookup over
UDP) and `resolv_hostname_at` (parses `/etc/hostname`). This
example uses the hosts-file path because it is the single
lookup libresolv covers that is fully hermetic in CI: no
network, no `/etc/hostname` requirement, no resolver dance.
Later examples can walk the DNS path when there is a
stable reference to look up.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
