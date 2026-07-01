# libs/asm/

Formatting and process helpers packaged as the static archive
`libasm.a`. Three routines: `print_string`, `print_int`, `sys_exit`.
These exist so future examples can call the helpers without
re-inlining `sys_write` boilerplate, and so the `%ifdef MACOS` fork
of the syscall numbers lives in exactly one place.

See [`../README.md`](../README.md) for the conventions shared by every
archive in `libs/` (calling convention, error convention, no-libc
policy). This archive predates the split into subdirectories — it
was the seed of `libs/` and moved down one level when `libs/tcp/`
was added.

## Exported symbols

| Symbol         | Args                     | Returns               | Notes                                                          |
| -------------- | ------------------------ | --------------------- | -------------------------------------------------------------- |
| `print_string` | `rdi = buf`, `rsi = len` | `rax` = bytes written | Wraps `sys_write(1, buf, len)`.                                |
| `print_int`    | `rdi = n` (signed i64)   | none                  | Decimal, handles negatives and `LLONG_MIN`.                    |
| `sys_exit`     | `rdi = status`           | noreturn              | Hides the `SYS_EXIT` number difference between macOS and Linux.|

Symbols are exported under their plain names (`print_string`, not
`_print_string`) on both platforms — the archive is meant for
assembly-to-assembly linking, not C interop.

## Build

### macOS

```bash
make
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the three object files into
`libasm.a` with `ar rcs`.

### Linux

```bash
make
```

On Linux, the same `make` invocation assembles with `nasm -f elf64`.

## How to link against `libasm.a` from an example

In the consumer's `.asm`:

```nasm
extern print_string                 ; from libs/asm/libasm.a

section .rodata
msg:     db "hello", 10
msg_len: equ $ - msg

section .text
_start:
_main:
    lea rdi, [msg]                  ; arg 1: buffer
    mov rsi, msg_len                ; arg 2: length
    call print_string               ; libasm prints it via sys_write
```

In the consumer's `Makefile`, append the archive to the link line.
For a consumer at `examples/NN-slug/`, the path is
`../../libs/asm/libasm.a`:

```makefile
LIBASM := ../../libs/asm/libasm.a

$(BIN): $(OBJ) $(LIBASM)
	$(LD) $(OBJ) $(LIBASM) -o $(BIN)
```

Building the consumer does not automatically build the archive. Run
`make -C ../../libs/asm` first, or add a recursive prerequisite to
the consumer Makefile.

## See also

- [`../tcp/`](../tcp/) — TCP socket primitives (`tcp_connect`,
  `tcp_send`, `tcp_recv`, `tcp_close`).
- [`../../docs/14-procedures.md`](../../docs/14-procedures.md) — the
  System V AMD64 calling convention these helpers follow.
- [`../../examples/20-shared-lib/`](../../examples/20-shared-lib/) —
  the example that first demonstrates linking against an external
  library (`libSystem` / `libc`).
