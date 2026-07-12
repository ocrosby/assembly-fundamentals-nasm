# 47 — timing

Measure elapsed wall-clock time across a `sleep_ms(50)`
call using libtime's `now_ms`. The classic "record now, do
work, record now again, subtract" pattern that every
benchmark is built on. Exits 42 when the observed elapsed
time lands in the plausible band.

First runnable that uses libtime as the *star*.

## Introduces

- **`now_ms` (libtime).** Wall-clock milliseconds since
  Unix epoch, returned as a single signed 64-bit integer.
  Wraps `gettimeofday` plus `tv_sec * 1000 + tv_usec / 1000`
  into one call.
- **The elapsed-time pattern.** Take two timestamps and
  subtract. Same shape for latency logging, benchmark
  timing, and rate limiting.

## Program flow

```
start = now_ms()
sleep_ms(50)
end   = now_ms()
elapsed = end - start
assert 40 <= elapsed < 500
exit(42)
```

## The plausibility band

The lower bound is 40 ms rather than 50 ms because kernel
scheduling and `poll(NULL, 0, 50)`-side rounding can shave
a few milliseconds off. The upper bound is 500 ms rather
than 100 ms because CI runners under load can stall for a
while; going strict would produce flaky failures on
unrelated PRs.

Wall-clock time can also jump backward if `ntpd` corrects
during the measurement — for elapsed-time work that must
be immune to that, use `monotonic_ms` on Linux (macOS
returns `-ENOSYS`; see [`docs/33-time.md`](../../docs/33-time.md)).

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
