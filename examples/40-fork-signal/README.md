# 40 — fork-signal

Fork a child that would sleep for 10 seconds, send it SIGTERM
from the parent, then `wait4` and confirm the child was
terminated by a signal (not a normal exit). Exits 42 on
success.

First runnable that uses libproc's `kill`. Demonstrates the
process-control triangle libproc was built for.

## Introduces

- **`kill(pid, sig)` (libproc).** Send a signal to a
  process. The child does not need to install a handler —
  the default action for SIGTERM is termination, which is
  what makes this example short.
- **`wait4` status-word interpretation.** The status word
  wait4 fills is the same on macOS and Linux (POSIX
  standardized it). The low 7 bits identify how the child
  died:

  | `status & 0x7f`     | Meaning                                        |
  | ------------------- | ---------------------------------------------- |
  | `0`                 | Normal exit; code is `(status >> 8) & 0xff`.   |
  | `0x7f`              | Stopped (WUNTRACED), not reaped.               |
  | anything else       | Terminated by that signal number.              |

  This example fires only in the third case.
- **The fork → kill → wait4 pattern.** The whole point of
  libproc: talk to your children via signals, then reap them.

## Program flow

```
call fork
    parent:
        r12 = child pid
        kill(r12, SIGTERM)                → 0
        wait4(r12, &status, 0, NULL)      → r12 (reaped pid)
        assert (status & 0x7f) == SIGTERM  # signal termination
        exit(42)
    child:
        sleep_ms(10000)                    # 10s if not killed
        exit(99)                           # sentinel: "not killed"
```

Sending SIGTERM immediately after `fork` is safe: if the
child has not yet been scheduled, the kernel queues the
signal in its pending set. As soon as the child is picked
by the scheduler, the queued signal is delivered — the
`sleep_ms` never has a chance to complete.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42` in about 100ms (well under the 10-second
sleep, because SIGTERM interrupts it).

## Next

- Back to [examples/README.md](../README.md).
