# 10 — write-file

Open `/tmp/nasm-write-file.txt` with `O_WRONLY | O_CREAT | O_TRUNC`
and mode `0644`, write `"written by nasm\n"` to it, close, and exit.
Builds on [09-read-file](../09-read-file/) by flipping the open
direction from read to write.

## Introduces

- The `O_WRONLY | O_CREAT | O_TRUNC` flag combination — create the
  file if it does not exist, truncate if it does.
- The **mode** argument in `rdx` (only meaningful with `O_CREAT`) —
  the file's permission bits. `420` in decimal is `0644` octal
  (rw-r--r--).
- The macOS/Linux `O_*` bitmask split: `O_CREAT` is `0x200` on
  macOS and `0x40` on Linux, `O_TRUNC` is `0x400` vs `0x200`. The
  `%ifdef MACOS` block picks the right constants.

## Build and run

```bash
make
./write-file                     # exit=0
cat /tmp/nasm-write-file.txt     # written by nasm
make clean
```

Expected: `/tmp/nasm-write-file.txt` exists and contains
`written by nasm\n`, `exit=0`.

## Next

- [11-copy-file](../11-copy-file/) — combine 09 and 10 into a mini
  `cp`.
