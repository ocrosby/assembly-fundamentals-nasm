# Comparison & Flags

Most decisions in assembly are made by *setting flags* with one instruction and *branching on flags* with the next.

## RFLAGS bits you will use

| Flag | Name           | Set when                                     |
|------|----------------|----------------------------------------------|
| `ZF` | Zero           | result was 0                                 |
| `SF` | Sign           | result's high bit was 1 (negative)           |
| `CF` | Carry          | unsigned overflow / borrow                   |
| `OF` | Overflow       | signed overflow                              |
| `PF` | Parity         | low byte of result has even parity (rarely used) |

## `cmp` — subtract, discard, keep flags

```nasm
            cmp     rax, rbx            ; flags as if (rax - rbx)
            je      .equal              ; jump if ZF=1
            jl      .less               ; jump if SF != OF (signed less)
            jb      .below              ; jump if CF=1   (unsigned less)
```

## `test` — AND, discard, keep flags

Use for "is this nonzero?" and bit checks.

```nasm
            test    rax, rax            ; sets ZF if rax == 0
            jz      .is_zero

            test    rax, 1 << 4         ; sets ZF if bit 4 clear
            jnz     .bit_set
```

## Signed vs unsigned conditional jumps

| Condition | Signed | Unsigned |
|-----------|--------|----------|
| equal     | `je`   | `je`     |
| not equal | `jne`  | `jne`    |
| `<`       | `jl`   | `jb`     |
| `<=`      | `jle`  | `jbe`    |
| `>`       | `jg`   | `ja`     |
| `>=`      | `jge`  | `jae`    |

Pick the column that matches the meaning of your data. Mixing them is a frequent bug.

## `setcc` — materialize a flag as 0 or 1

```nasm
            cmp     rax, rbx
            setl    al                  ; al = (rax < rbx) ? 1 : 0
            movzx   eax, al
```

## Next

- [Jumps](12-jumps.md)
