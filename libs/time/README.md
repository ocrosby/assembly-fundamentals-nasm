# libs/time/

Wall-clock and (eventually) monotonic-time primitives packaged as
the static archive `libtime.a`. Tracks the syscall-backed portion
of POSIX
[`<sys/time.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/sys_time.h.html)
and
[`<time.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/time.h.html),
but only where a single kernel syscall exists on **both** macOS and
Linux and has the same signature. Functions that are libc-side
constructions on either platform are deliberately left out; see
"Not here yet" below.

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/` follows.

## Version

**v1.5** — fourth `util/` helper: `format_time_rfc1123(seconds,
out)`, which writes the fixed-form RFC 1123 date string
`Sun, 06 Nov 1994 08:49:37 GMT` (exactly 29 bytes, no NUL) to
the caller's buffer given a `u64` Unix-seconds value.
Pure integer arithmetic — Howard Hinnant's `civil_from_days`
turns a day count into `(year, month, day)` in branchless
code, and the weekday is `(days + 4) mod 7` since
1970-01-01 was Thursday. Motivated by the HTTP `Date:`
response header (RFC 7231 §7.1.1.1), but produces the same
format RFC 5322, RFC 5321, and any other "wall clock as a
fixed-width string" caller wants.

**v1.4** — third `util/` helper: `monotonic_ms()`, a
deliberately asymmetric wrapper. Linux gets real
`clock_gettime(CLOCK_MONOTONIC, ...)` monotonic milliseconds;
macOS gets an honest `-ENOSYS` because the raw-syscall path
to Darwin's monotonic clock is closed off (see
"Not here yet" for the full story). This is the exception
to the archive's "same shape on both platforms or not
shipped" discipline — the return convention stays uniform
(`rax >= 0` success, negative errno failure), and the
failure code lets callers detect unavailability and fall
back to whatever suits them.

**v1.3** — second `util/` helper: `now_ms()`, the "give me
wall-clock time as a single 64-bit integer" call. Wraps
`gettimeofday` + `tv_sec * 1000 + tv_usec / 1000` into one
step, saving log and benchmark code from re-writing the
combine every time.

**v1.2** — first `util/` helper: `time_diff_us(late, early)`,
a pure computation that returns the signed microsecond
difference between two `struct timeval`s.

**v1.1** — `gettimeofday` (fixed) plus `sleep_ms` (portable
millisecond sleep) and `getrusage` (CPU-time accounting). Also
fixed the latent v1.0 bug where the `gettimeofday` wrapper
left Darwin's 3rd syscall argument uninitialized (see below).

**v1.0** — `gettimeofday` only. Scaffolding release.

## Exported symbols

### `syscall/` — direct kernel wrappers

| Symbol           | Arguments                                    | Returns              |
| ---------------- | -------------------------------------------- | -------------------- |
| `gettimeofday`   | `tv*` (`struct timeval*`), `tz*` (`void*`)   | 0 or negative errno  |
| `sleep_ms`       | `ms` (unsigned int)                          | 0 or negative errno  |
| `getrusage`      | `who` (int), `rusage*` (`struct rusage*`)    | 0 or negative errno  |

### `util/` — pure-computation helpers

| Symbol           | Arguments                                     | Returns                                                     |
| ---------------- | --------------------------------------------- | ----------------------------------------------------------- |
| `time_diff_us`   | `late*`, `early*` (both `struct timeval*`)    | Signed microsecond delta (`late - early`). Negative sentinels reversed args. |
| `now_ms`         | (none)                                        | Wall-clock milliseconds since Unix epoch (signed 64-bit), or negative errno if `gettimeofday` failed. |
| `monotonic_ms`   | (none)                                        | **Linux only**: monotonic milliseconds since some kernel-chosen origin (signed 64-bit). **macOS**: always returns `-ENOSYS` (`-78`). |

`gettimeofday` writes the current wall clock to `*tv` as a
`struct timeval { time_t tv_sec; suseconds_t tv_usec; }` at
microsecond precision. `tz` is deprecated on both platforms —
pass NULL. Passing a non-NULL `tz` either fills obsolete fields
(macOS) or is silently ignored (Linux); it is not portable.

`sleep_ms` suspends the calling thread for approximately `ms`
milliseconds via `poll(NULL, 0, ms)` — the well-known portable
trick that borrows the millisecond timeout of the `poll` syscall
without needing `nanosleep`. Precision is bounded by the kernel
scheduler tick.

`getrusage` reports resource usage since process start.
`who = RUSAGE_SELF (0)` reports the calling process's totals;
`who = RUSAGE_CHILDREN (-1)` reports the sum over waited-on
children. Only the first two `struct rusage` fields —
`ru_utime` and `ru_stime`, each a `struct timeval` — are
guaranteed to have identical layout across platforms;
`syscall.inc` exposes `RU_UTIME_OFF = 0` and `RU_STIME_OFF = 16`.
Later fields differ in width and count between macOS and
Linux — callers that want them handle the per-platform tail
themselves.

`time_diff_us` computes `late - early` in microseconds,
returning a signed 64-bit result. It is a pure computation:
no syscall, no allocation, and no assumption beyond the
`struct timeval` layout shared with `gettimeofday`. Reversed
arguments produce a negative value — a convenient sanity
sentinel for benchmark harnesses that want to detect an
obvious argument-order mistake. Overflow requires the two
timevals to be more than ~292,471 years apart; callers can
treat that limit as effectively absent.

`now_ms` is not pure — it calls `gettimeofday` internally —
but the return shape (a single signed 64-bit integer) makes
it fit alongside `time_diff_us` in the same `util/` bucket.
The computation is `tv_sec * 1000 + tv_usec / 1000`, so
precision is milliseconds derived from `gettimeofday`'s
microseconds. Wall-clock caveats apply — NTP jumps, DST
transitions, manual admin adjustments. For elapsed-time
measurements pin two calls close together and subtract.

`monotonic_ms` is the archive's only intentionally
asymmetric symbol. On Linux the body issues
`clock_gettime(CLOCK_MONOTONIC, &ts)` via `SYS 228` and
returns `ts.tv_sec * 1000 + ts.tv_nsec / 1_000_000`. On
macOS the body immediately returns `-78` (`-ENOSYS`) —
Darwin's raw-syscall path to monotonic time is closed
(`SYS_clock_gettime_nsec_np` at 462 returns `-1` from
userspace on Darwin 25+), and the mach trap for
`mach_absolute_time` returns a value in an unstable
undocumented unit. The commpage and libSystem paths are
banned by the archive's no-libc policy. A wrapper that
silently returned `gettimeofday`-derived milliseconds on
macOS would be lying about monotonicity; this file refuses
to lie. Callers who need best-effort monotonic time on
macOS check for `-ENOSYS` and fall back to `now_ms`
themselves, with the understanding that they are getting
a wall clock, not a monotonic one.

## Darwin gettimeofday 3-arg fix

v1.0's `gettimeofday` wrapper was a straight 2-arg pass-through.
That is correct on Linux (`SYS_gettimeofday = 96` really is
2-arg) but **wrong on macOS**: Darwin's `SYS_gettimeofday = 116`
takes a third argument, `uint64_t *mach_absolute_time`. When
`rdx` carries a non-zero value on entry, the kernel writes 8
bytes through it, corrupting whatever memory was there. v1.0
shipped this bug because the asm smoke test's bss layout
absorbed the stray write silently, and the C smoke test
inadvertently linked to libc's `gettimeofday` on macOS (the C
declaration lacked the `__asm__("gettimeofday")` label needed
to bypass Mach-O's `_gettimeofday` name mangling).

v1.1 fixes the wrapper (adds `xor edx, edx` before the syscall
on macOS) and fixes the C smoke test to actually exercise
libtime's `gettimeofday` via `__asm__` labels — matching the
pattern used in `libs/io/test/c-smoke.c` and
`libs/sock/test/c-smoke.c`.

## Layout — `struct timeval`

Both macOS and Linux use a 16-byte `struct timeval`:

| Field    | Offset | Size          | Range                    |
| -------- | ------ | ------------- | ------------------------ |
| `tv_sec` | 0      | 8 bytes       | Unix seconds since epoch |
| `tv_usec`| 8      | 4 bytes (macOS) / 8 bytes (Linux) | 0..999999      |

`tv_usec` is `int32_t` on macOS (`suseconds_t = __int32_t`) and
`long` on Linux, but the stored value is always in the range
0..999999, so a 32-bit read at offset 8 is safe on both
platforms. `libs/time/syscall/syscall.inc` exposes
`TV_SEC_OFF = 0`, `TV_USEC_OFF = 8`, and `TIMEVAL_SIZE = 16` for
NASM consumers.

## Not here yet

The obvious remaining candidates all run into a macOS wall:

- **`clock_gettime`.** No numbered POSIX equivalent on Darwin.
  The closest interface, `clock_gettime_nsec_np` at syscall 462,
  is now **blocked from userspace** — invoking it via the raw
  `syscall` instruction returns `-1` (verified on Darwin 25.3,
  x86_64). Apple flags the entry with `NO_SYSCALL_STUB` and
  routes libc's `clock_gettime` through the commpage instead.
  There is no path to POSIX `clock_gettime` semantics from raw
  assembly without either:
  - reading the commpage (version-fragile addresses that
    change between Darwin releases), or
  - linking libSystem (breaks the [no-libc
    policy](../README.md#archives) every archive in `libs/`
    follows).

  libtime therefore **defers `clock_gettime` indefinitely on
  macOS**. Linux callers who need nanosecond precision can call
  the Linux syscall (`SYS_clock_gettime = 228`) directly; the
  archive will not paper over the platform gap with an
  asymmetric wrapper.
- **`nanosleep`.** Same shape. Linux `SYS_nanosleep = 35` is
  clean; Darwin has no numbered equivalent, and its
  `__semwait_signal` (334) needs a semaphore fd rather than a
  timeout. `sleep_ms` (this release) gives 90% of the value at
  millisecond precision; nanosecond precision on macOS is
  gated on the same commpage/libSystem trade-off as
  `clock_gettime`.
- **`mach_absolute_time`.** Historically a mach trap
  (`0x1000003`), but modern Darwin routes the userspace name
  through the commpage — the trap still fires but returns a
  value in an unstable, undocumented unit that no longer
  matches `mach_timebase_info`. Not useful without libSystem.
- **`time`.** Linux has `SYS_time = 201`; macOS does not. Since
  `gettimeofday` already exists on both, a separate `time`
  wrapper adds no capability, so it will not ship.

The precision gap is a real limitation. It is why every
wrapper here is honest about being **microsecond**- rather
than **nanosecond**-precise, and why the syscall-side of the
archive stops at three symbols rather than papering over the
macOS story with a wrapper that would silently degrade on
one platform.

## Building

```bash
make -C libs/time
```

Produces `libs/time/libtime.a`.

## Testing

```bash
make -C libs/time test
```

The test target builds the archive first, then runs the harness
in [`test/run.sh`](test/run.sh):

- **`time-smoke`** — sub-checks 1–6 verify `gettimeofday`
  plausibility (post-2023 `tv_sec`, valid `tv_usec`,
  monotonic between successive calls); 7–B verify
  `sleep_ms(50)` actually delays for 40–2000 ms; C–D verify
  `getrusage(RUSAGE_SELF, &ru)` returns a `struct rusage`
  with non-negative `ru_utime` and `ru_stime`; E–F verify
  `time_diff_us` matches the manual computation and returns
  a negative value for reversed arguments.
- **`c-smoke`** — links `libtime.a` from a C toolchain and
  exercises every exported symbol with `__asm__` labels
  pinning the reference to libtime's bare names (bypassing
  Mach-O's `_gettimeofday` mangling that would otherwise fall
  back to libc). Cross-checks `gettimeofday` against libc's
  `time(NULL)` (±60 s), verifies `sleep_ms(50)` elapsed at
  least 20 ms, confirms `getrusage` produced non-negative
  CPU time, and asserts `time_diff_us` agrees with the
  manually-computed elapsed microseconds.

Both must print `PASS` for the target to exit 0.

## See also

- [`../asm/`](../asm/) — formatting helpers useful for printing
  timestamps once you have them.
- [`../sock/`](../sock/) — `poll` is the fallback nanosleep
  substitute on macOS (see "Not here yet").
