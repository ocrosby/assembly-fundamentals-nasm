# System Calls

A syscall asks the kernel to do something — read, write, exit. macOS and Linux share the register convention for arguments and return, but their syscall numbers differ.

## Register convention

Both platforms follow the same layout for the `syscall` instruction:

| Register | Purpose                       |
|----------|-------------------------------|
| `rax`    | syscall number                |
| `rdi`    | arg 1                         |
| `rsi`    | arg 2                         |
| `rdx`    | arg 3                         |
| `r10`    | arg 4 (note: **not** `rcx`)   |
| `r8`     | arg 5                         |
| `r9`     | arg 6                         |
| `rax`    | return value (or `-errno`)    |

`rcx` and `r11` are clobbered by the `syscall` instruction.

## macOS

macOS sets the **high byte** of `rax` to the syscall class and the low bytes to the call number. For BSD calls (which is what you want for `write`/`exit`), that prefix is `0x2000000`.

| Name       | Number             | Args              |
|------------|--------------------|-------------------|
| `exit`     | `0x2000001`        | status            |
| `write`    | `0x2000004`        | fd, buf, count    |

```nasm
    mov rax, 0x2000004               ; sys_write
    mov rdi, 1                       ; fd = stdout
    lea rsi, [rel msg]
    mov rdx, msg_len
    syscall
```

Apple discourages direct syscalls and may break them between macOS releases. For anything beyond a toy, link `libSystem` and call `write`, `exit`, etc., as ordinary functions. See [Linking](18-linking.md).

For a category-organized list of the common BSD calls and the `rax` value each one needs, see the [macOS Syscall Reference](syscalls/macos/README.md).

## Linux

Numbers come from `/usr/include/asm/unistd_64.h`:

| Name       | Number | Args              |
|------------|--------|-------------------|
| `read`     | 0      | fd, buf, count    |
| `write`    | 1      | fd, buf, count    |
| `open`     | 2      | path, flags, mode |
| `close`    | 3      | fd                |
| `exit`     | 60     | status            |

```nasm
    mov rax, 1                       ; sys_write
    mov rdi, 1
    mov rsi, msg
    mov rdx, msg_len
    syscall
```

## Errors

On both platforms, a negative `rax` means the call failed and the magnitude is `errno`.

## Next

- [Macros](17-macros.md)
