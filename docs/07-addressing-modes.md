# Addressing Modes

Operands fall into three families: **immediate**, **register**, and **memory**.

## Immediate

A constant baked into the instruction.

```nasm
    mov rax, 42
    add rbx, 0x10
```

## Register

A value held in a CPU register.

```nasm
    mov rax, rbx
```

## Memory

Square brackets dereference an address. The general form is:

```
[ base + index * scale + displacement ]
```

| Part         | Allowed                              |
|--------------|--------------------------------------|
| base         | any 64-bit GPR                       |
| index        | any 64-bit GPR except `rsp`          |
| scale        | `1`, `2`, `4`, or `8`                |
| displacement | a signed integer or label            |

### Examples

```nasm
    mov rax, [buf]           ; direct
    mov rax, [rbx]           ; register-indirect
    mov rax, [rbx + 8]       ; base + disp
    mov rax, [rbx + rcx]     ; base + index
    mov rax, [rbx + rcx*4]   ; base + index*scale
    mov rax, [rbx + rcx*8 + 16] ; full form
    mov rax, [rel buf]       ; RIP-relative
```

## `lea` — address arithmetic without dereferencing

`lea` computes the effective address but does **not** read memory. It is also a fast way to do `base + index*k + d` arithmetic:

```nasm
    lea rax, [rbx + rcx*4 + 8] ; rax = rbx + rcx*4 + 8
```

## Sizing memory operands

The processor needs to know how wide the access is. If neither operand pins it down, prefix it:

```nasm
    inc qword [counter]
```

## Next

- [Data Movement](08-data-movement.md)
