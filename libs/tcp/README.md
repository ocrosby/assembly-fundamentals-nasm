# libs/tcp/

TCP socket primitives packaged as the static archive `libtcp.a`. Four
routines: `tcp_connect`, `tcp_send`, `tcp_recv`, `tcp_close`. They
issue `socket` / `connect` / `read` / `write` / `close` syscalls
directly; there is no libc dependency and no hostname resolution
(callers supply a numeric IPv4 address).

See [`../README.md`](../README.md) for the conventions shared by
every archive in `libs/` — calling convention, error convention, and
the no-libc policy.

## Exported symbols

| Symbol        | Args                                                | Returns                                 | Behavior                                                                     |
| ------------- | --------------------------------------------------- | --------------------------------------- | ---------------------------------------------------------------------------- |
| `tcp_connect` | `rdi = ip` (u32 network order); `rsi = port` (u16) | `rax` = fd or negative errno            | Creates AF_INET SOCK_STREAM socket, connects, returns fd. Closes on failure. |
| `tcp_send`    | `rdi = fd`; `rsi = buf`; `rdx = len`               | `rax` = bytes written or negative errno | Wraps `write(fd, buf, len)`. Partial writes possible.                        |
| `tcp_recv`    | `rdi = fd`; `rsi = buf`; `rdx = len`               | `rax` = bytes read or negative errno    | Wraps `read(fd, buf, len)`. `rax == 0` means peer closed.                    |
| `tcp_close`   | `rdi = fd`                                          | `rax` = 0 or negative errno             | Wraps `close(fd)`.                                                           |

### The `ip` argument

`tcp_connect` takes the destination IP as a `u32` **already in
network byte order**. For 127.0.0.1 — bytes `0x7F 0x00 0x00 0x01` on
the wire — that is the little-endian `u32` `0x0100007F`:

```nasm
extern tcp_connect                  ; from libs/tcp/libtcp.a

    mov edi, 0x0100007F             ; 127.0.0.1
    mov esi, 8080                   ; port — library byte-swaps
    call tcp_connect                ; rax = fd or negative errno
```

There is deliberately no hostname support in `libtcp.a`. Hostname
resolution would require `getaddrinfo`, which lives in libc — and
this repository's `libs/` archives are strictly libc-free.

## Build

### macOS

```bash
make                                # produces libs/tcp/libtcp.a
```

The Makefile detects Darwin via `uname -s` and assembles with
`nasm -f macho64 -DMACOS`, then packs the four object files into
`libtcp.a` with `ar rcs`.

### Linux

```bash
make                                # produces libs/tcp/libtcp.a
```

On Linux the same `make` assembles with `nasm -f elf64`.

## Linking against `libtcp.a`

In the consumer's `.asm`:

```nasm
extern tcp_connect
extern tcp_send
extern tcp_recv
extern tcp_close
```

In the consumer's `Makefile`, append the archive to the link line.
For a consumer at `examples/NN-slug/`, the path is
`../../libs/tcp/libtcp.a`:

```makefile
LIBTCP := ../../libs/tcp/libtcp.a

$(BIN): $(OBJ) $(LIBTCP)
	$(LD) $(OBJ) $(LIBTCP) -o $(BIN)
```

Building the consumer does not automatically build the archive; run
`make -C ../../libs/tcp` first.

## See also

- [`../asm/`](../asm/) — formatting and process helpers
  (`print_string`, `print_int`, `sys_exit`). Consumers of `libtcp.a`
  typically also link `libasm.a` to print the bytes they receive.
- [`../../examples/20-shared-lib/`](../../examples/20-shared-lib/) —
  the example that first demonstrates linking against an external
  library. The mechanics are the same; the difference is that
  `libtcp.a` is an in-repo static archive rather than libc.
