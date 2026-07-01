# 11 — copy-file

A minimal `cp`: open `/tmp/nasm-copy-src.txt` for reading and
`/tmp/nasm-copy-dst.txt` for writing, loop `read` → `write` in
4 KiB chunks until the source EOFs, close both descriptors, and
exit. The last of the I/O series. Builds on
[10-write-file](../10-write-file/) by holding two open descriptors
in parallel.

## Introduces

- Managing two open fds concurrently: source in `r12`, destination
  in `r13` (both callee-saved so they survive the intermediate
  `syscall`s).
- Layered error handling: a failure at each stage jumps to the
  cleanup label that closes exactly the fds that are already open
  (`.fail_close_both`, `.fail_close_src`, `.fail`).
- The full open/read/write/close vocabulary in a single program.

## Build and run

```bash
printf 'copy source content\n' > /tmp/nasm-copy-src.txt
make
./copy-file
cat /tmp/nasm-copy-dst.txt        # copy source content
make clean
```

Expected: `/tmp/nasm-copy-dst.txt` matches
`/tmp/nasm-copy-src.txt`, `exit=0`.

## Next

- [12-countdown](../12-countdown/) — the sequence returns to
  control flow with a counted loop.

