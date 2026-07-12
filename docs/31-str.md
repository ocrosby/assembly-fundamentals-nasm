# Strings and byte buffers

The [`libstr`](../libs/str/) archive is the pure-computation
piece of the toolkit — no syscalls, no OS-specific branches,
no allocation. Eleven routines cover three families that
consumer code was inlining by hand before it was extracted.

## Three families

| Family                | Routines                                        | Shape                                  |
| --------------------- | ----------------------------------------------- | -------------------------------------- |
| Raw-byte              | `memcpy`, `memset`, `memcmp`, `memchr`          | Pointer + explicit length. No NUL.     |
| NUL-terminated string | `strlen`, `strcmp`, `strncmp`, `strchr`, `strcpy` | Pointer + trailing `'\0'`.           |
| Integer conversion    | `atoi`, `itoa`                                  | Decimal ASCII ↔ signed 64-bit integer. |

Each routine returns per the C standard so callers who
already know the C shape need no translation table.

## Byte-at-a-time is deliberate

`memcmp`, `strlen`, `strcmp`, `strncmp`, `strchr`, and
`strcpy` scan bytes one at a time. A SIMD or SWAR scan can
read past the end of the input buffer when the terminator or
`n` is not word-aligned — that trick is legal in glibc
(malloc always overallocs) but this archive makes no
allocation assumption about its callers. The pathological
"strlen crashes on a page-boundary string" bug that hits
naive SIMD implementations does not exist here.

`memcpy` and `memset` use `rep movsb` / `rep stosb`, which
the modern x86-64 core turns into a fast-string microcoded
copy — competitive with hand-rolled 8-byte loops at the
small buffer sizes this library targets, and honest about
not touching bytes past `n`.

## The `strcpy` contract (and the `strncpy` non-decision)

`strcpy(dst, src)` copies through and including the
terminator. Callers are responsible for ensuring `dst` has
at least `strlen(src) + 1` bytes of space; overrun is
undefined behavior. Overlap is not permitted either.

There is deliberately **no `strncpy`**. Its truncation
semantics have surprised C programmers for four decades:
if `src` is longer than `n` bytes, `strncpy` writes exactly
`n` bytes with **no** trailing NUL; if `src` is shorter,
`strncpy` pads with NULs to `n` bytes. Neither behavior is
what most callers want when they type "strncpy". A caller
who wants a bounded copy computes `strlen` and calls
`memcpy` explicitly — three lines that document the intent
instead of hiding it.

## `atoi` and `itoa` are a symmetric pair

`atoi(s)` walks a NUL-terminated decimal string. Semantics
match POSIX:

- Leading whitespace (space, tab, LF) is skipped.
- One optional sign character (`+` or `-`) follows.
- Digits accumulate until the first non-digit byte.
- Empty input, all-whitespace input, and inputs starting
  with a letter all return 0.

No overflow check — values above `2^63 - 1` wrap silently.
That matches glibc's `atoi` at optimized settings and lets
the routine stay a leaf function without stack scratch.

`itoa(n, buf)` writes the decimal representation into
`buf` and returns the byte count — no trailing NUL. The
return-byte-count shape pairs with `memcpy` and libsock's
`send_all`; callers who want a C string append their own
`'\0'` at `buf[rax]`. Maximum output is 20 bytes
(`-9223372036854775808`).

`LLONG_MIN` is handled correctly. `neg` on the sign-only
bit pattern leaves `rax` as the unsigned quantity `2^63`,
and `div` is unsigned, so the divide loop produces the
right digits without a special case.

## No `n = 0` traps

Every routine that takes an `n` argument treats `n = 0` as
legal and returns without touching memory. `memcpy(dst, src,
0)` returns `dst` unchanged; `memcmp(_, _, 0)` returns 0
regardless of contents; `memchr(_, _, 0)` returns NULL.
Callers don't have to guard against the empty-buffer case
before dispatching to a libstr routine.

## What isn't a libstr helper

- **`memmove`.** libstr's `memcpy` requires non-overlapping
  buffers. A separate `memmove` for overlap-safe copies
  would be trivial to add but no consumer needs it yet.
- **Unicode / wide characters.** libstr is byte-oriented.
  UTF-8 works incidentally because the ASCII subset agrees;
  multi-byte codepoint iteration and normalization are not
  in scope.
- **Regular expressions, tokenizers, hashing.** These sit
  on top of libstr in the same way libio's composed helpers
  sit on top of its syscall wrappers — they'll live in a
  future `libstr/util/` if a real consumer motivates them.

## See also

- [`libs/str/`](../libs/str/) — the full archive with every
  routine's per-symbol contract.
- [`27-libraries.md`](27-libraries.md) — the archive index
  this chapter is a companion to.
- [`examples/37-config-load`](../examples/37-config-load/)
  and [`examples/39-number-store`](../examples/39-number-store/)
  — runnables that combine `memcmp` + `strchr` + `atoi`
  and `itoa` + `atoi` respectively.

## Next

- Back to [docs/README.md](README.md).
