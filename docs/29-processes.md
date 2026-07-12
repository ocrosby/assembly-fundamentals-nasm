# Processes

Signals ([`28-signals`](28-signals.md)) let a process
influence another once it exists. This chapter covers the
"once it exists" half: how [`libproc`](../libs/proc/) creates
processes with `fork`, replaces their image with `execve`,
and reaps them with `wait4`.

## fork returns twice

The classic surprise: `fork` returns to *two* different
processes. In the parent, `rax` holds the new child's pid. In
the child, `rax` is `0`. A negative `rax` means the fork
itself failed (the calling process never had a child) and
there is only one return.

```nasm
call fork
test rax, rax
js  .fail                ; -errno; still just one process
jz  .child               ; rax == 0: we are the child
; parent path: rax = child pid
```

Everything is copied: file descriptors, memory mappings, the
signal mask. Both processes continue from the same
instruction. `MAP_SHARED` mappings observe each other's
writes ([`32-mmap-shared`](../examples/32-mmap-shared/) walks
this); `MAP_PRIVATE` mappings are copy-on-write.

## execve replaces the image

`execve` throws away the caller's text, data, and heap and
replaces them with a new binary loaded from disk. Open file
descriptors are inherited unless they had the `FD_CLOEXEC`
flag set via `fcntl` (see [`libio`'s v1.8](../libs/io/#v18--fd-flags--advisory-locks)).
On success `execve` does not return — the new program's
entry point runs instead. On failure `rax` holds `-errno`.

The typical shape:

```nasm
call fork
test rax, rax
js  .fail
jz  .exec_child
; parent: wait for the child
...

.exec_child:
    lea rdi, [path]      ; "/bin/echo"
    lea rsi, [argv]      ; NULL-terminated char*[]
    lea rdx, [envp]      ; NULL-terminated char*[]
    call execve
    ; only reached if execve failed
    mov rax, SYS_exit
    mov edi, 1
    syscall
```

## wait4 status word

`wait4(pid, &status, options, rusage)` reaps a terminated
child and fills a 32-bit status word that both platforms
agree on:

| `status & 0x7f`       | Meaning                                        |
| --------------------- | ---------------------------------------------- |
| `0`                   | Normal exit; code is `(status >> 8) & 0xff`.   |
| `0x7f`                | Stopped, not reaped (requires `WUNTRACED`).    |
| anything else         | Terminated by that signal number.              |

The [`40-fork-signal`](../examples/40-fork-signal/) example
fires only in the third case: it sends SIGTERM and confirms
`status & 0x7f == 15`. `options = 0` blocks; `WNOHANG` polls
and returns `0` if the child has not exited yet. `rusage`
can be NULL when the caller does not need CPU-time accounting.

## The spawn_wait helper

Fork + execve + wait4 is common enough that libproc ships
[`spawn_wait`](../libs/proc/util/spawn_wait.asm) as a
composed helper:

```nasm
spawn_wait(path, argv, envp) → exit code or -errno
```

Blocks until the child exits, decodes the wait4 status
internally, and returns the exit code (or `-errno` for a
fork/exec failure). Signal-terminated children are surfaced
as `128 + signal_number`, matching what shells report.
[`33-spawn-child`](../examples/33-spawn-child/) demonstrates
the one-call use.

## See also

- [`libs/proc/`](../libs/proc/) — every syscall wrapper
  behind the model above (fork, execve, wait4, kill,
  getpid, getppid) plus the `spawn_wait` helper.
- [`28-signals.md`](28-signals.md) — sending signals to
  the processes this chapter created.
- [`27-libraries.md`](27-libraries.md) — the archive index.

## Next

- Back to [docs/README.md](README.md).
