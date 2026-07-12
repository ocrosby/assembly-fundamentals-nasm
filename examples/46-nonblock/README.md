# 46 — nonblock

Toggle `O_NONBLOCK` on a pipe's read end via `fcntl`, then
attempt a read on the empty pipe. The read returns `-EAGAIN`
instead of blocking forever. Exits 42 on that observation.

First runnable that uses libio's `fcntl`. Non-blocking fds
are the underlying mechanic of every event loop, every
async runtime, and every real-shape server that handles
more than one connection at a time.

## Introduces

- **`fcntl(fd, F_GETFL, 0)` and `fcntl(fd, F_SETFL, flags)`.**
  The classic "read current flags, OR in a new bit, write
  them back" idiom for toggling a per-fd flag without
  clobbering the others.
- **`O_NONBLOCK`.** With this bit set, a read on an fd
  with no data available returns `-EAGAIN` immediately
  rather than parking the caller until data arrives.
  `write` and `send` return `-EAGAIN` when the kernel
  buffer is full, giving the caller a chance to yield.
- **`EAGAIN` platform difference.** `35` on macOS,
  `11` on Linux — but libio's syscall wrappers normalize
  via `SYSCALL_NORM`, so callers compare against a symbolic
  `-EAGAIN` and let the assembler pick the number.

## Program flow

```
pipe(pipefd)
old_flags = fcntl(pipefd[0], F_GETFL, 0)
fcntl(pipefd[0], F_SETFL, old_flags | O_NONBLOCK)  → 0
read(pipefd[0], buf, 1)                             → -EAGAIN
close(pipefd[0..1])
exit(42)
```

## Why the read-modify-write dance?

`F_SETFL` replaces the entire flags word. If you want to
preserve `O_APPEND` or other bits the kernel already set
when the fd was created, read them back with `F_GETFL`
first, OR in the bit you want, and write the whole thing
back. Every real-world "make this fd non-blocking" call
does this dance.

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
