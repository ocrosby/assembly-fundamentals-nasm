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

**v1.0** — `gettimeofday`. The bare minimum needed to answer "what
time is it?" from raw assembly, and enough to prove the archive
scaffolding is correct before v1.1 adds monotonic-time and sleep
primitives.

## Exported symbols

| Symbol           | Arguments                                    | Returns              |
| ---------------- | -------------------------------------------- | -------------------- |
| `gettimeofday`   | `tv*` (`struct timeval*`), `tz*` (`void*`)   | 0 or negative errno  |

`gettimeofday` writes the current wall clock to `*tv` as a
`struct timeval { time_t tv_sec; suseconds_t tv_usec; }` at
microsecond precision. `tz` is deprecated on both platforms —
pass NULL. Passing a non-NULL `tz` either fills obsolete fields
(macOS) or is silently ignored (Linux); it is not portable.

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

`libtime` v1.0 exposes exactly one wrapper on purpose. The obvious
next candidates all have macOS gotchas that need a considered
approach rather than a straight `SYS_*` mapping:

- **`clock_gettime`.** Darwin does not expose the POSIX
  `clock_gettime` as a numbered BSD syscall. The closest kernel
  interface is `clock_gettime_nsec_np` at syscall 462, which
  returns nanoseconds directly in `rax` for a `clock_id_t`
  argument — non-portable and shaped nothing like Linux's
  `clock_gettime(clock_id, struct timespec*)` at syscall 228.
  libtime v1.1 will provide `clock_gettime` with a per-platform
  implementation body that hides the split.
- **`nanosleep`.** Linux exposes `SYS_nanosleep` at 35 with a
  clean `(const struct timespec *req, struct timespec *rem)`
  signature. macOS routes `nanosleep` through
  `__semwait_signal` (syscall 334), which needs a semaphore fd
  in addition to the timeout — not something a caller wants to
  set up. libtime v1.1 will offer a `sleep_ms` helper that
  wraps `nanosleep` on Linux and a `poll(NULL, 0, ms)` fallback
  on macOS.
- **`mach_absolute_time`.** macOS's monotonic clock is a Mach
  trap, not a BSD syscall — accessible by placing a negative
  syscall number in `rax`. libtime v1.1 will expose a
  `monotonic_ns` helper that dispatches to the trap on macOS
  and `clock_gettime(CLOCK_MONOTONIC, ...)` on Linux.
- **`time`.** Linux has `SYS_time` at 201; macOS does not — libc's
  `time()` on Darwin is a wrapper around `gettimeofday`. If
  every value can already be recovered from `gettimeofday`, a
  separate wrapper adds no capability, so `time` will not ship.

Each deferred wrapper is a design task, not a naming task —
adding it well means picking one signature that hides the
per-platform mechanism from callers.

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

- **`time-smoke`** — calls `gettimeofday` twice and checks the
  returned struct is plausible (post-2023 `tv_sec`, `tv_usec` in
  range) and non-decreasing between calls.
- **`c-smoke`** — links `libtime.a` from a C toolchain and
  compares its `gettimeofday` return against libc's
  `time(NULL)`, verifying the two agree within ±60 seconds.

Both must print `PASS` for the target to exit 0.

## See also

- [`../asm/`](../asm/) — formatting helpers useful for printing
  timestamps once you have them.
- [`../sock/`](../sock/) — `poll` is the fallback nanosleep
  substitute on macOS (see "Not here yet").
