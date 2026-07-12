# File locking with `flock`

When two processes want to write to the same file — a log
rotator and its daemon, two instances of a CLI editing the
same config, two workers appending to a shared journal —
they need a rendezvous point outside their own memory. The
filesystem itself provides one: an advisory lock associated
with the file. [`libio`](../libs/io/) exports the BSD
variant, `flock(2)`, because it has the cleanest scope rules
of any lock POSIX ships.

## The three operations

```
flock(fd, operation) -> 0 or -errno
```

`operation` is one of `LOCK_SH`, `LOCK_EX`, or `LOCK_UN`,
optionally OR'd with the modifier `LOCK_NB`:

| Value       | Numeric | Meaning                                              |
| ----------- | ------: | ---------------------------------------------------- |
| `LOCK_SH`   |       1 | Shared — many holders, all readers.                  |
| `LOCK_EX`   |       2 | Exclusive — one holder, blocks others.               |
| `LOCK_UN`   |       8 | Release whatever lock this open holds.               |
| `LOCK_NB`   |       4 | Modifier: fail with `-EWOULDBLOCK` instead of block. |

The numeric values are identical on macOS and Linux, so
libsig's `syscall.inc` defines them once.

## Advisory, not mandatory

The kernel checks and updates the lock; it does not enforce
it. A process that opens the file and calls `read` or
`write` without ever calling `flock` succeeds regardless of
who else holds a lock. Every participating process has to
cooperate.

That is fine for the "single application coordinating
between its own instances" case (log rotators, PID files,
`/etc/passwd` editors) — every party is the same program and
knows to check. It is not fine for security-sensitive
workloads.

## Scope: per open file description, not per fd or inode

This is the property that makes `flock` different from
`fcntl` POSIX locks:

- **`dup2` and `fork` share the lock.** They inherit the
  open file description, so the lock travels with it.
- **Two separate `open` calls to the same path do not
  share the lock.** Each `open` creates a fresh file
  description; each holds its own claim.
- **The lock persists as long as any fd on the shared
  description is open.** Closing one duplicate does not
  release the lock; only the last close does.

The [`48-flock`](../examples/48-flock/) example exercises
the second rule explicitly: the parent `open`s a lock file,
acquires `LOCK_EX`, then `fork`s. The child re-`open`s the
same path (fresh file description), tries
`LOCK_EX | LOCK_NB`, and observes `-EWOULDBLOCK` because
the parent still holds the lock.

## Why not `fcntl` POSIX locks?

`fcntl(fd, F_SETLK, &flock_struct)` also exists, and has two
things `flock` does not:

1. Byte-range granularity (lock offsets 100..199, leave the
   rest unlocked).
2. Correct behavior across NFS.

But it has a widely-known trap: **closing any fd on the file
releases all locks the process holds on that inode.** A
library that opens the file to read some metadata and then
closes it can silently release the caller's lock. Linux
added *open file description locks* (`F_OFD_SETLK`) to fix
this; macOS has not.

For the mutex use case — one holder, whole file — `flock`'s
per-open-file-description scope is the safer default.
libio ships `flock` and skips POSIX locks entirely.

## Non-blocking acquisition

`LOCK_NB` turns `flock` from a blocking primitive into a
try-lock:

```nasm
mov edi, r12d               ; fd
mov esi, LOCK_EX | LOCK_NB
call flock
cmp rax, -EWOULDBLOCK
je .lock_held_by_someone_else
```

The errno value is `-EWOULDBLOCK` (which is `-EAGAIN` on
Linux, `-35` on macOS) and libio's `syscall.inc` exposes
both names as the same constant. Callers that want to poll
for the lock retry on a small delay rather than spin.

## See also

- [`libs/io/syscall/flock.asm`](../libs/io/syscall/flock.asm)
  — the wrapper; the numeric flag values live in
  `libs/io/syscall/syscall.inc`.
- [`30-io.md`](30-io.md) — the file family this lock sits
  next to.
- [`27-libraries.md`](27-libraries.md) — the archive index
  this chapter is a companion to.
- [`examples/48-flock`](../examples/48-flock/) — the
  runnable that exercises `LOCK_EX` + `LOCK_NB` and
  demonstrates the per-open-file-description scope.

## Next

- Back to [docs/README.md](README.md).
