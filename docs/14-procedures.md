# Procedures

A procedure is a labeled block of code reached with `call` and exited with `ret`.

## `call` and `ret`

```nasm
    call my_proc             ; push return address, jump
    ; ... execution resumes here after ret ...

my_proc: ; ... body ...
    ret                      ; pop address from stack, jump to it
```

`call` pushes the address of the next instruction; `ret` pops it back into `rip`.

## System V AMD64 calling convention (Linux, macOS)

| Role | Registers |
|------|-----------|
| Integer args 1–6 | `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` |
| Integer return  | `rax` (and `rdx` for 128-bit) |
| Float args 1–8  | `xmm0`–`xmm7` |
| Float return    | `xmm0` |
| Caller-saved (scratch) | `rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`–`r11`, all `xmm*` |
| Callee-saved (preserve) | `rbx`, `rbp`, `r12`–`r15`, `rsp` |

Caller-saved means "if you need it after a `call`, save it yourself." Callee-saved means "if you use it, push/pop it around your function body."

## Stack alignment

At the moment of `call`, `rsp` must be **16-byte aligned minus 8** (so it becomes 16-aligned after the return address is pushed). If you make calls from your function, align before them — typically with `sub rsp, 8` or by pushing an extra register.

## A complete example

```nasm
global square
section .text

square: ; int64_t square(int64_t x)  -- x in rdi, result in rax
    mov rax, rdi
    imul rax, rdi
    ret
```

Calling it:

```nasm
    mov rdi, 7
    call square              ; rax = 49
```

## Runnable

- [examples/07-square/](../examples/07-square/) — `square` called from `_main`
  with the result returned as the exit status. `make && make run`.

## Next

- [The Stack](15-stack.md)
