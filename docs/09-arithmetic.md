# Arithmetic

Integer math on x86-64. All instructions below update RFLAGS (see [Comparison & Flags](11-comparison.md)).

## Addition and subtraction

```nasm
    add rax, rbx             ; rax += rbx
    sub rax, 1               ; rax -= 1
    inc rcx                  ; rcx += 1
    dec rcx                  ; rcx -= 1
    neg rax                  ; rax = -rax
```

`inc`/`dec` do not update the carry flag — use `add reg, 1` in flag-sensitive code.

## Multiplication

| Form                  | Effect                                |
|-----------------------|---------------------------------------|
| `mul rcx`             | unsigned: `rdx:rax = rax * rcx`       |
| `imul rcx`            | signed:   `rdx:rax = rax * rcx`       |
| `imul rax, rbx`       | signed:   `rax = rax * rbx`           |
| `imul rax, rbx, 10`   | signed:   `rax = rbx * 10`            |

The two- and three-operand `imul` forms are preferred when you do not need the full 128-bit result.

## Division

`div` and `idiv` divide a 128-bit dividend in `rdx:rax` by the operand. **Clear `rdx` first** for unsigned division; use `cqo` to sign-extend `rax` into `rdx` for signed division.

```nasm
    xor rdx, rdx
    mov rax, 100
    mov rcx, 7
    div rcx                  ; rax = 14, rdx = 2 (remainder)
```

```nasm
    mov rax, -100
    cqo                      ; sign-extend rax -> rdx:rax
    mov rcx, 7
    idiv rcx                 ; signed division
```

A division by zero raises `#DE`; the OS turns it into `SIGFPE` on macOS/Linux.

## Worked example — addition via the exit status

A complete Linux program that returns `7 + 5` as its exit status. Reading the result with `echo $?` is the simplest way to "see" the answer without writing to stdout.

```nasm
global _start

section .text
_start:
    mov rax, 7
    mov rbx, 5
    add rax, rbx             ; rax = 12

    mov rdi, rax             ; exit status = 12
    mov rax, 60              ; sys_exit (Linux)
    syscall
```

```bash
nasm -f elf64 add.asm -o add.o
ld add.o -o add
./add ; echo $?     # 12
```

## Pitfalls

- Operand widths must match — `add rax, ebx` is an error.
- `mul`/`div` clobber `rdx` even when you don't expect it.
- `neg` of `INT64_MIN` overflows back to itself; check OF if it matters.

## Runnable

- [examples/03-add/](../examples/03-add/) — the addition program above as a
  complete cross-platform source file. `make && make run`.

## Next

- [Bitwise & Shifts](10-bitwise.md)
