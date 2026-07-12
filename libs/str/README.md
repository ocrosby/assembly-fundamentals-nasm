# libs/str/

Byte-manipulation helpers packaged as the static archive
`libstr.a`. Nine routines cover the raw-byte pair
(`memcpy` / `memset` / `memcmp` / `memchr`) and the
NUL-terminated-string set (`strlen` / `strcmp` / `strncmp` /
`strchr` / `strcpy`). Every export is pure computation — no
syscalls, no OS-specific branches, no `%ifdef MACOS` — so the
source has no per-platform paths and the archive builds
identically on macOS and Linux.

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Version

**v1.1** — four search / bounded-compare / copy routines
extend the archive: `memchr`, `strchr`, `strncmp`, and
`strcpy`. Each matches its C standard-library counterpart
so callers who already know the C shape need no translation
table. `strncmp` fills the "bounded strcmp" hole that came
up as soon as v1.0 shipped; `memchr` and `strchr` cover the
"find first byte" pattern; `strcpy` writes a NUL-terminated
run into a caller-owned buffer. No `strncpy` — its truncation
semantics are famously confusing; callers wanting a bounded
copy compute `strlen` and call `memcpy` explicitly.

**v1.0** — first shipping cut of libstr. Five routines cover
the byte-manipulation surface that consumer code was inlining
by hand: the raw-byte trio (`memcpy`, `memset`, `memcmp`) and
the NUL-terminated pair (`strlen`, `strcmp`). Every routine
returns per the C standard so callers who already know the C
shape do not need a translation table.

## Exported symbols

| Symbol    | Arguments                                    | Returns                                                                            |
| --------- | -------------------------------------------- | ---------------------------------------------------------------------------------- |
| `memcpy`  | `rdi = dst`, `rsi = src`, `rdx = n`          | `rdi` (the original `dst`).                                                        |
| `memset`  | `rdi = dst`, `rsi = c` (byte), `rdx = n`     | `rdi` (the original `dst`). Only the low byte of `c` is written.                   |
| `memcmp`  | `rdi = a`, `rsi = b`, `rdx = n`              | 0 if equal, positive if `a > b`, negative if `a < b` (unsigned bytes).             |
| `memchr`  | `rdi = s`, `rsi = c` (byte), `rdx = n`       | Pointer to the first byte equal to `c` in the first `n` bytes, or NULL on miss.    |
| `strlen`  | `rdi = s` (NUL-terminated)                   | Length in bytes, excluding the terminator.                                         |
| `strcmp`  | `rdi = a`, `rsi = b` (both NUL-terminated)   | 0 if equal, positive if `a > b`, negative if `a < b` (unsigned bytes).             |
| `strncmp` | `rdi = a`, `rsi = b`, `rdx = n`              | Like `strcmp` but stops after `n` bytes or the first shared terminator.            |
| `strchr`  | `rdi = s` (NUL-terminated), `rsi = c` (byte) | Pointer to the first byte equal to `c`, or NULL. `c = 0` matches the terminator.   |
| `strcpy`  | `rdi = dst`, `rsi = src` (NUL-terminated)    | `rdi` (the original `dst`). Copies through and including the terminator.           |

`memcpy`, `memset`, and `strcpy` return the original `dst`
pointer for call-chaining. `memcmp` and `strcmp` / `strncmp`
return a signed 64-bit integer in `rax` — the value always
fits in `[-255, 255]`, so callers wanting the traditional C
`int` can truncate the low 32 bits. `memchr` and `strchr`
return either a pointer into the input string or NULL (0).

Byte-at-a-time is deliberate for the compare, scan, and
NUL-terminated routines. A SIMD or SWAR scan can read past
the end of the input buffer when the boundary is not
aligned; that trick is legal in glibc (malloc always
overallocs) but this archive makes no allocation assumption
about its callers. `memcpy` and `memset` use `rep movsb` /
`rep stosb`, which the modern x86-64 core turns into a
fast-string microcoded copy — competitive with hand-rolled
8-byte loops at the small buffer sizes this library targets,
and honest about not touching bytes past `n`.

Symbols are exported under their plain names (`memcpy`, not
`_memcpy`) on both platforms. The archive is meant for
assembly-to-assembly linking. C consumers wanting to call into
it must use an `__asm__("memcpy")` label to bypass Mach-O's
`_memcpy` mangling, matching the pattern in
[`libs/io/test/c-smoke.c`](../io/test/c-smoke.c).

## Overlap and n = 0

- `memcpy`, `strcpy`: buffers must not overlap. Overlap is
  undefined behavior; there is no `memmove` in this archive.
- `memset`, `memcmp`, `memchr`: no overlap constraint.
- Every routine treats `n = 0` as legal and returns without
  touching memory (`memcpy` / `memset` return `dst`;
  `memcmp` returns 0).

## Building

### macOS

```bash
make -C libs/str
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the object files into
`libstr.a` with `ar rcs`. `-DMACOS` is inert for libstr's
sources — none of them branch on the flag — but it keeps the
build flags uniform across every archive in `libs/`.

### Linux

```bash
make -C libs/str
```

On Linux, the same `make` invocation assembles with
`nasm -f elf64`.

## Testing

```bash
make -C libs/str test
```

The test target builds the archive first, then runs the harness
in [`test/run.sh`](test/run.sh):

- **`str-smoke`** — sub-checks 1–3 verify `memcpy` on a 12-byte
  buffer plus the `n = 0` canary; 4–6 verify `memset` fills all
  bytes, ignores the high bits of `c`, and honors `n = 0`; 7–A
  verify `memcmp` on equal, negative-differ, positive-differ
  (unsigned), and `n = 0` inputs; B–D verify `strlen` at length
  0, 5, and 13; E–H verify `strcmp` for equal, `<`, `>`
  (shorter side smaller), and `>` (byte value greater).
  **v1.1** adds I–K (`memchr` hit / miss / `n = 0`), L–N
  (`strchr` hit / needle == '\0' / miss), O–S (`strncmp`
  equal-in-n / differ-in-n / bounded-below-diff / shorter-<-longer
  / `n = 0`), and T–U (`strcpy` copies + preserves trailing
  sentinels / returns dst).

libasm's `panic` is on the link line because the smoke's
`.fail` path calls into it. Sub-check IDs are single characters
so a failure prints one of `FAIL:1` through `FAIL:U` on stderr
and the process exits 1.

## Linking against `libstr.a` from an example

In the consumer's `.asm`:

```nasm
extern strlen                       ; from libs/str/libstr.a

section .rodata
msg: db "hello, world", 0

section .text
_start:
_main:
    lea rdi, [msg]                  ; arg 1: NUL-terminated string
    call strlen                     ; rax = 12
    ; ... use the length
```

In the consumer's `Makefile`, append the archive to the link
line. For a consumer at `examples/NN-slug/`, the path is
`../../libs/str/libstr.a`:

```makefile
LIBSTR := ../../libs/str/libstr.a

$(BIN): $(OBJ) $(LIBSTR)
	$(LD) $(OBJ) $(LIBSTR) -o $(BIN)
```

Building the consumer does not automatically build the archive.
Run `make -C ../../libs/str` first, or add a recursive
prerequisite to the consumer Makefile.

## See also

- [`../asm/`](../asm/) — formatting helpers (`print_string`,
  `print_int`) that pair naturally with `strlen`.
- [`../../docs/14-procedures.md`](../../docs/14-procedures.md) —
  the System V AMD64 calling convention these helpers follow.
