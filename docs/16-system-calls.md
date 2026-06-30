# System Calls

A syscall asks the kernel to do something — read, write, exit. The convention differs between Linux and macOS.

## Linux

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

Common numbers (from `/usr/include/asm/unistd_64.h`):

| Name       | Number | Args              |
|------------|--------|-------------------|
| `read`     | 0      | fd, buf, count    |
| `write`    | 1      | fd, buf, count    |
| `open`     | 2      | path, flags, mode |
| `close`    | 3      | fd                |
| `exit`     | 60     | status            |

```nasm
    mov rax, 1
    mov rdi, 1
    mov rsi, msg
    mov rdx, msg_len
    syscall                  ; write(1, msg, msg_len)
```

## macOS

macOS sets the **high byte** of `rax` to the syscall class and the low bytes to the call number. For BSD calls (which is what you want for `write`/`exit`), that prefix is `0x2000000`.

| Name       | Number             | Args              |
|------------|--------------------|-------------------|
| `write`    | `0x2000004`        | fd, buf, count    |
| `exit`     | `0x2000001`        | status            |

```nasm
    mov rax, 0x2000004
    mov rdi, 1
    lea rsi, [rel msg]
    mov rdx, msg_len
    syscall
```

Apple discourages direct syscalls and may break them between macOS releases. For anything beyond a toy, link `libSystem` and call `write`, `exit`, etc., as ordinary functions. See [Linking](18-linking.md).

## Errors

On both platforms, a negative `rax` means the call failed and the magnitude is `errno`.

## Next

- [Macros](17-macros.md)
