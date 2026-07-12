# 48 — flock-mutex

Show `flock(2)` as a filesystem-backed mutex. Parent opens a
lock file, acquires `LOCK_EX`, forks. Child opens the same
file **separately**, attempts `LOCK_EX | LOCK_NB`, and
observes `-EWOULDBLOCK` because the parent holds the lock.
Parent reaps the child and exits 42.

First runnable that uses libio's `flock`. Filesystem locks
are what most log rotators, PID files, and multi-writer
CLIs use to serialize access.

## Introduces

- **`flock(fd, op)` (libio).** Advisory lock on an open
  file description. `LOCK_EX` for exclusive, `LOCK_SH`
  for shared, `LOCK_UN` to release. OR in `LOCK_NB` to
  make the call non-blocking (returns `-EWOULDBLOCK`
  instead of waiting).
- **Per-open-file-description scope.** flock is not
  per-fd or per-inode — it is per `open` call. If parent
  and child shared the inherited fd via `fork`, they
  would *share* the lock and the child's `LOCK_NB` would
  succeed. Each side opens the file separately so they
  own distinct file descriptions and distinct claims.

## Program flow

```
parent:
    open(path, O_RDWR|O_CREAT, 0600)     → parent_fd
    flock(parent_fd, LOCK_EX)            → 0
    fork()
    ├── child:
    │       open(path, O_RDWR|O_CREAT, 0600)  → child_fd (own open)
    │       flock(child_fd, LOCK_EX|LOCK_NB)  → -EWOULDBLOCK
    │       close(child_fd); _exit(0)
    └── parent:
            wait4(child); verify exit == 0
            close(parent_fd) — releases the lock
            unlink(path)
            exit(42)
```

## Why flock instead of `fcntl(F_SETLK)`?

`fcntl` POSIX locks are more granular (per byte range) but
have a well-known "closing any fd on the file releases all
locks the process holds on that inode" trap. `flock` is
simpler: one lock per open, released only when that open
closes. For the mutex use case it is the safer choice.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
