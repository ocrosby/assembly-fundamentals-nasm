# 09 — read-file

A minimal `cat`: open `/tmp/nasm-read-file.txt`, read its contents
in 4 KiB chunks, write each chunk to stdout, close the file, and
exit. Builds on [08-echo-loop](../08-echo-loop/) by replacing the
stdin fd (0) with an fd returned by `sys_open`.

## Introduces

- `sys_open` (with `O_RDONLY`, no mode) and `sys_close`.
- Saving the returned file descriptor in `r12` — a callee-saved
  register that survives across the intermediate `syscall`s.
- Error handling: `js .fail` — a negative `rax` from `open` or
  `read` is `-errno`; branch to a cleanup exit.

Paired with [docs/16-system-calls.md](../../docs/16-system-calls.md).

## Build and run

The example expects `/tmp/nasm-read-file.txt` to exist. Seed one
first, then run:

```bash
printf 'read by NASM\n' > /tmp/nasm-read-file.txt
make
./read-file                    # prints "read by NASM"
make clean
```

Expected: file contents on stdout, `exit=0`. If the file is
missing or unreadable, `exit=1`.

## Next

- [10-write-file](../10-write-file/) — the other half of file
  I/O: creating a file.
