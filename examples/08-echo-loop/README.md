# 08 — echo-loop

Read from standard input in 128-byte chunks and echo each chunk to
standard output, until `sys_read` returns `0` (EOF). A minimal `cat`
for stdin. Builds on [07-write-line](../07-write-line/) by pulling
the read/write pair inside a `.loop:` label.

## Introduces

- Driving `sys_read` in a loop.
- Detecting EOF: `test rax, rax` / `jz .done` after `read`.
- Detecting errors: `js .done` — `rax < 0` means `-errno`.

## Build and run

```bash
make
printf 'line one\nline two\n' | ./echo-loop
make clean
```

Expected: whatever is piped to stdin is echoed to stdout, then
`exit=0` when the pipe closes.

## Next

- [09-read-file](../09-read-file/) — same loop shape, but the
  input is a file on disk.
