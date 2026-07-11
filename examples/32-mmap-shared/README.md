# 32 — mmap-shared

Use an anonymous `MAP_SHARED` page as a one-byte IPC channel
between a parent process and a `fork()`'d child. Child writes
42; parent, after `wait4()` reaps the child, reads the byte
back through the same mapping. Exit 42 on success. First
example combining libio (`mmap`, `munmap`) with libproc
(`fork`, `wait4`).

## Introduces

- **`MAP_SHARED`.** Third mmap flag combination after
  30-shared-mapping's anonymous `MAP_PRIVATE` and
  31-mmap-file's file-backed `MAP_PRIVATE`. `MAP_SHARED`
  means changes made through the mapping propagate to
  every process that inherits or re-maps the same
  underlying kernel object. Anonymous mappings created
  with `MAP_SHARED` are shared with any child inherited
  via `fork` — the pattern this example demonstrates.
- **Linking two archives on the same `ld` line.** Same
  mechanic as 29-server-client (libsock + libproc);
  30 and 31 needed only libio. Here libio + libproc.
- **Cross-process synchronization via `wait4`.** The
  parent does not read the byte until `wait4` returns —
  that is what guarantees the child's store has hit the
  page. Any earlier read would race the child.

## Why exit 42

`_exit(42)` in the child would produce the same exit code
without needing any shared memory — the parent already sees
child status via `wait4`. The point of the exit trick is
end-to-end verification of the shared page: the value 42
travels from the child's process (its `mov byte [rbx], 42`),
through the kernel-mapped page, into the parent's
`movzx r12d, byte [rbx]`, and out through the parent's exit.
Any break in the chain — MAP_PRIVATE instead of MAP_SHARED,
a missing `wait4`, an unrelated segfault — produces a
different exit code.

## Program flow

```
   parent                              child
   ------                              -----
   mmap MAP_SHARED|MAP_ANON            (inherits rbx via fork)
     → rbx (shared page address)
   fork() ────────────►
                        \\             mov byte [rbx], 42
                        \\             _exit(0)
   wait4(child_pid, ...)
   byte = *(u8*)rbx                    → 42
   munmap(rbx, 4096)
   exit(byte)                          → 42
```

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`.

## Next

- Back to [examples/README.md](../README.md).
