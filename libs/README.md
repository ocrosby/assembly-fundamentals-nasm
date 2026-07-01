# libs/

Reusable NASM archives for the assembly-fundamentals-nasm repo. Each
subdirectory produces a single static archive (`.a`) that consumer
examples can link against. Archives here are **not part of the
constructive example sequence** in `examples/`; they exist as
infrastructure that later examples opt into.

All archives in this directory share the same conventions:

- **Direct syscalls only** — no `libc` / `libSystem` dependency.
  Consumer binaries link with a bare `ld` invocation; they do not
  need `-lSystem` or `-lc`, and callers do not have to honor the
  16-byte-alignment-before-`call` rule to invoke these routines.
- **System V AMD64 ABI** — arguments in `rdi`, `rsi`, `rdx`, `rcx`,
  `r8`, `r9`; return value in `rax`. Callee-saved registers
  (`rbx`, `rbp`, `r12`–`r15`) are preserved by every routine.
- **Uniform error convention** — routines that can fail return a
  negative `errno` in `rax` on failure and a non-negative value on
  success, on **both** platforms. The macOS BSD carry-flag error
  convention is normalized inside each library so callers see the
  Linux `-errno` shape everywhere.

## Archives

| Path              | Archive     | Purpose                                                                                        |
| ----------------- | ----------- | ---------------------------------------------------------------------------------------------- |
| [`asm/`](asm/)    | `libasm.a`  | Formatting and process helpers (`print_string`, `print_int`, `sys_exit`).                      |
| [`tcp/`](tcp/)    | `libtcp.a`  | TCP socket primitives (`tcp_connect`, `tcp_send`, `tcp_recv`, `tcp_close`).                    |

Each subdirectory's `README.md` documents the exported symbols and
calling conventions for that archive.

## Building

Each archive is built independently:

```bash
make -C libs/asm
make -C libs/tcp
```

There is no aggregate `libs/Makefile` yet — two archives is not enough
to justify one.

## Linking against multiple archives

Consumer binaries list every archive they use on the `ld` command
line. Static-archive linkers scan left-to-right for unresolved
symbols, so the archive containing the *references* must appear
before the archive containing the *definitions*. When a future
`libhttp.a` calls into `libtcp.a`, for instance:

```
ld ... consumer.o libhttp.a libtcp.a -o consumer
```

When both archives are independent — as `libasm.a` and `libtcp.a` are
today — the order does not matter.

## Platform notes

macOS is the primary target for this repository — see
[`.claude/rules/platform-priority.md`](../.claude/rules/platform-priority.md).
Both platforms are supported; a change that works on macOS but breaks
the Linux ELF path is a regression.
