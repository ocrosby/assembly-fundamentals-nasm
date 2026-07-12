# Time

The [`libtime`](../libs/time/) archive tracks the
syscall-backed portion of POSIX `<sys/time.h>` and
`<sys/resource.h>`. Wall clock, CPU-time accounting,
millisecond sleeping — the things a program needs when it
cares about *when* it is running or *how long* it has been.

## `struct timeval` and the shared layout

`gettimeofday(&tv, NULL)` fills a 16-byte `struct timeval`:

```
+0   tv_sec   (8 bytes) — Unix seconds since epoch
+8   tv_usec  (4 bytes) — microseconds within tv_sec, 0..999999
```

Both macOS and Linux use this layout. The `tv_usec` field is
32-bit on macOS (`suseconds_t = __int32_t`) and 64-bit on
Linux (`long`), but the stored value is always in the
0..999999 range, so a 32-bit read at offset 8 is safe on both
platforms. `syscall.inc` exposes `TV_SEC_OFF`, `TV_USEC_OFF`,
and `TIMEVAL_SIZE` so callers reference the offsets by name.

The `tz` argument to `gettimeofday` is deprecated. Pass
`NULL`; libtime's v1.1 fixed a latent bug where the wrapper
left Darwin's 3rd syscall argument (`mach_absolute_time*`)
uninitialized, which was corrupting whatever memory the
random register value happened to point at.

## `sleep_ms` — millisecond sleep via `poll`

Neither macOS nor Linux exposes a raw `nanosleep` under a
number that agrees between platforms. Instead of shipping
two wrappers, libtime uses the well-known trick:
`poll(NULL, 0, ms)` blocks for `ms` milliseconds and returns
0. Both platforms honor the timeout, and the syscall exists
on both by the same number.

Precision is bounded by the kernel scheduler tick (usually a
few milliseconds). `sleep_ms(50)` reliably sleeps ≥40 ms and
usually <100 ms — the time-smoke's sub-checks A and B check
those bounds.

## `getrusage` — CPU time so far

`getrusage(RUSAGE_SELF, &ru)` reports resource usage since
process start. Only the first two `struct rusage` fields —
`ru_utime` and `ru_stime`, each a `struct timeval` — have
identical layout across platforms:

```
+0   ru_utime  (16 bytes, timeval)
+16  ru_stime  (16 bytes, timeval)
```

`syscall.inc` exposes `RU_UTIME_OFF` and `RU_STIME_OFF`.
Later fields (page faults, block I/O, context switches) have
different widths and offsets on the two platforms; callers
who want them handle the per-platform tail themselves.
`RUSAGE_SELF = 0`, `RUSAGE_CHILDREN = -1`.

## Util helpers built on those wrappers

- `time_diff_us(late, early)` — signed microsecond delta
  between two `struct timeval`s. Pure computation.
- `now_ms()` — `gettimeofday` + `tv_sec * 1000 + tv_usec /
  1000` in one call. Wall-clock milliseconds since Unix
  epoch as a single 64-bit integer. Not pure — it calls
  `gettimeofday` internally.
- `monotonic_ms()` — see the asymmetry note below.

## `monotonic_ms` and the macOS asymmetry

`monotonic_ms` is the archive's only intentionally
asymmetric symbol. On Linux it wraps
`clock_gettime(CLOCK_MONOTONIC, &ts)` via syscall 228 and
returns `ts.tv_sec * 1000 + ts.tv_nsec / 1_000_000`. On
macOS the body immediately returns `-78` (`-ENOSYS`).

The reason: Darwin's raw-syscall path to monotonic time is
closed off. `SYS_clock_gettime_nsec_np` at 462 returns `-1`
from userspace on Darwin 25+; the mach trap for
`mach_absolute_time` returns a value in an unstable
undocumented unit that no longer matches
`mach_timebase_info`. The commpage and libSystem paths are
banned by libtime's no-libc policy.

A wrapper that silently returned `gettimeofday`-derived
milliseconds on macOS would be lying about monotonicity;
this archive refuses to lie. Callers who need best-effort
monotonic time on macOS check for `-ENOSYS` and fall back to
`now_ms` themselves, with the understanding that they are
getting a wall clock, not a monotonic one.

## What isn't in libtime

- **`clock_gettime`** on macOS — closed via commpage
  (documented as deferred; see libtime's README).
- **`nanosleep`** — same macOS story.
- **`mach_absolute_time`** — value units are unstable.
- **`time`** — Linux-only syscall; `gettimeofday` already
  covers the "current second" story on both platforms.

## See also

- [`libs/time/`](../libs/time/) — the full archive with
  every wrapper's per-symbol contract.
- [`27-libraries.md`](27-libraries.md) — the archive
  index this chapter is a companion to.

## Next

- Back to [docs/README.md](README.md).
