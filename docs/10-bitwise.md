# Bitwise & Shifts

Bit-level operations: logic, shifts, and rotates.

## Boolean logic

```nasm
    and rax, rbx             ; bitwise AND
    or rax, rbx              ; bitwise OR
    xor rax, rbx             ; bitwise XOR
    not rax                  ; bitwise NOT (one's complement)
```

`xor rax, rax` is the canonical idiom for **zeroing a register** — shorter and faster than `mov rax, 0`.

## Shifts

| Mnemonic | Direction | Fill bit            | Semantics             |
|----------|-----------|---------------------|-----------------------|
| `shl`    | left      | 0                   | logical / arithmetic  |
| `shr`    | right     | 0                   | unsigned / logical    |
| `sar`    | right     | sign bit            | signed / arithmetic   |
| `sal`    | left      | 0                   | alias for `shl`       |

```nasm
    shl rax, 3               ; rax *= 8
    shr rax, 1               ; rax /= 2 (unsigned)
    sar rax, 1               ; rax /= 2 (signed, rounds toward -inf)
```

The count is either an immediate or `cl`:

```nasm
    mov cl, 5
    shl rax, cl
```

## Rotates

Rotate bits without losing them.

```nasm
    rol rax, 4               ; rotate left
    ror rax, 4               ; rotate right
    rcl rax, 1               ; rotate-through-carry left
    rcr rax, 1               ; rotate-through-carry right
```

## Single-bit operations

```nasm
    bt rax, 3                ; CF = bit 3 of rax
    bts rax, 3               ; set bit 3
    btr rax, 3               ; reset bit 3
    btc rax, 3               ; complement bit 3
```

## Common patterns

```nasm
    and rax, ~0xff           ; clear low byte
    or rax, 1 << 5           ; set bit 5
    xor rax, 1 << 7          ; toggle bit 7
    test rax, rax            ; set ZF if rax == 0
```

## Next

- [Comparison & Flags](11-comparison.md)
