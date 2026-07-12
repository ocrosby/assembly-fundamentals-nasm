# 39 — number-store

End-to-end showcase for libio + libstr composition. Writes
three decimal integers as newline-separated ASCII to a
scratch file, reads the file back through `file_read_all`,
parses each line with `atoi`, and exits with the running sum.

Expected: `exit=42` (12 + 13 + 17).

## Introduces

- **`itoa` + `atoi` as a symmetric pair.** libstr v1.2's
  conversion routines let the example serialize integers to
  disk and reparse them without touching libc.
- **`file_write_all` + `file_read_all` composed.** libio
  v1.13 dumps the buffer; libio v1.12 hands it back as a
  PROT_READ mmap view. The two were designed to compose —
  this example proves it.
- **`strchr` as a line iterator.** No structural difference
  from `strchr` elsewhere in libstr, but this is the first
  example that uses it as the "advance to next line"
  primitive that every text-format parser needs.

## File format

Three lines, each a decimal integer terminated by `LF`:

```
12
13
17
```

Total 9 bytes. Values chosen so their sum matches the
`exit=42` sentinel every mmap and libio example in this
repo shares.

## Program flow

```
# Write phase — build the buffer with itoa, dump with file_write_all
n1 = itoa(12, scratch + 0);  scratch[n1] = '\n'
n2 = itoa(13, scratch + n1 + 1); scratch[n1 + 1 + n2] = '\n'
n3 = itoa(17, scratch + n1 + 2 + n2); scratch[...] = '\n'
file_write_all(path, scratch, total)

# Read + parse phase
file_read_all(path, &addr, &size)
cursor = addr; sum = 0
repeat 3 times:
    sum += atoi(cursor)                 # stops at '\n'
    cursor = strchr(cursor, '\n') + 1   # advance past the LF
munmap(addr, size)
exit(sum)                                # 42
```

## Build and run

```bash
make
make run
make clean
```

Expected: `exit=42`. The scratch file
`/tmp/nasm-number-store.txt` contains the three integers on
their own lines after the run.

## Next

- Back to [examples/README.md](../README.md).
