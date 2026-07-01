# 06 — read-line

Read up to 128 bytes from standard input into a `.bss` buffer, then
echo those bytes back. On a line-buffered TTY (the default), `read`
returns as soon as the user hits Enter, so the newline is part of
what gets echoed. Builds on [05-read-char](../05-read-char/) by
generalizing the byte count from 1 to N.

## Introduces

- `equ` for an assemble-time constant (`BUF_SIZE equ 128`) used as
  both the `.bss` reservation size and the `rdx` argument to
  `sys_read`.
- Using `rax` (bytes actually read) as the write length — you write
  exactly what you read.

## Build and run

```bash
make
printf 'hello\n' | ./read-line       # echoes "hello\n"
make clean
```

Expected on input `hello\n`: echoes `hello\n`, `exit=0`.

## Next

- [07-write-line](../07-write-line/) — the output counterpart: a
  fixed-length line in one call.
