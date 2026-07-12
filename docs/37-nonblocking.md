# Non-blocking I/O

By default a read on an empty pipe, an empty socket, or a
terminal with no pending input *blocks* — the syscall does
not return until data arrives or the peer closes. That is
usually what you want; it lets a program pause cheaply while
the kernel is doing the work. It is the wrong default the
moment you need to service more than one fd from one thread,
or make progress on a timeout, or refuse to hang. The escape
hatch is a single per-fd flag: `O_NONBLOCK`.

## What `O_NONBLOCK` changes

With `O_NONBLOCK` set, any I/O call that would have blocked
returns immediately with `-EAGAIN` (which is the same value
as `-EWOULDBLOCK` on both platforms):

| Call         | Blocking behavior                | With `O_NONBLOCK`                   |
| ------------ | -------------------------------- | ----------------------------------- |
| `read`       | Wait for data.                   | Return `-EAGAIN` if no data ready.  |
| `write`      | Wait for buffer space.           | Return `-EAGAIN` if no room.        |
| `accept`     | Wait for a client connect.       | Return `-EAGAIN` if none pending.   |
| `connect`    | Wait for the handshake.          | Return `-EINPROGRESS` immediately.  |
| `recv/send`  | Wait for data / buffer.          | Return `-EAGAIN`.                   |

The flag applies to the open file description, not to a
single call. Every subsequent read/write on that fd sees the
non-blocking behavior until the flag is cleared or the
description is dropped.

## Setting the flag with `fcntl`

`O_NONBLOCK` is a *file-status flag*, so it goes through
`fcntl(F_GETFL / F_SETFL)`. The idiomatic sequence is a
read-modify-write of the whole flag word:

```nasm
; fd is in ebx
mov edi, ebx
mov esi, F_GETFL
xor edx, edx
call fcntl
test rax, rax
js .fail
mov r13, rax                    ; save current flags

mov edi, ebx
mov esi, F_SETFL
mov rdx, r13
or  rdx, O_NONBLOCK             ; add O_NONBLOCK
call fcntl
test rax, rax
js .fail
```

The read-modify-write is not optional. `F_SETFL` overwrites
the whole flag word, so a naive `fcntl(fd, F_SETFL, O_NONBLOCK)`
also clears `O_APPEND` and any other status flags the
description was carrying.

Only four flags are actually settable via `F_SETFL`:
`O_APPEND`, `O_NONBLOCK`, `O_ASYNC`, `O_DIRECT`. The others
in the returned word — access mode, `O_CLOEXEC`, and so on
— are silently ignored on write.

## Setting it at `open`

The flag can also be OR'd into the `open` mode:

```nasm
lea rdi, [path]
mov esi, O_RDWR | O_NONBLOCK
xor edx, edx
call open
```

This avoids the read-modify-write and races nothing against
another thread using the same fd. It is the preferred form
whenever the fd is created inside the current program;
`fcntl` is the fallback for fds inherited from elsewhere
(stdin, an accepted socket, a `dup`).

## `-EAGAIN` is the whole point

The [`46-nonblock`](../examples/46-nonblock/) example is a
minimal demonstration: create a pipe, `fcntl` the read end
to `O_NONBLOCK`, `read` from it with no data queued, and
observe `-EAGAIN` in `rax`. That is the successful outcome
— the syscall did what it promised, which is to *not*
block.

A blocking read on the same empty pipe would sit in the
kernel until someone wrote a byte or closed the write end.
With `O_NONBLOCK` the caller gets control back immediately
and can go do something else — service another fd, check a
timer, log a metric.

## Non-blocking is only half the story

`-EAGAIN` tells you the fd is not ready, but not *when* it
will be. Spinning on it burns CPU. The other half of the
pattern is `poll(2)`: hand the kernel the list of fds you
care about, sleep until at least one is ready, then loop
back to the non-blocking reads. Non-blocking I/O without
`poll` is a busy-wait; non-blocking I/O with `poll` is an
event loop.

## See also

- [`libs/io/syscall/fcntl.asm`](../libs/io/syscall/fcntl.asm)
  — the wrapper, plus the `F_GETFL` / `F_SETFL` / `O_NONBLOCK`
  constants in `libs/io/syscall/syscall.inc`.
- [`30-io.md`](30-io.md) — the blocking file family this
  chapter modifies.
- [`35-multiplexing.md`](35-multiplexing.md) — the `poll`
  primitive that closes the "wait for ready" gap
  `O_NONBLOCK` leaves open.
- [`examples/46-nonblock`](../examples/46-nonblock/) — the
  runnable that sets `O_NONBLOCK` and observes `-EAGAIN`
  on an empty pipe.

## Next

- Back to [docs/README.md](README.md).
