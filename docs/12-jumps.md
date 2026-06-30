# Jumps

Transfer control to another address.

## Unconditional

```nasm
    jmp .label               ; relative jump within function
    jmp rax                  ; indirect through register
    jmp [table + rcx*8]      ; indirect through memory (jump table)
```

## Conditional (`jcc`)

A conditional jump tests RFLAGS (set by `cmp`, `test`, arithmetic). See [Comparison & Flags](11-comparison.md) for the full table.

```nasm
    cmp rax, 0
    je .zero                 ; jump if equal
    jne .nonzero             ; jump if not equal
    jl .negative             ; jump if signed-less
    jge .nonneg              ; jump if signed >=
```

## A worked example — `abs(rax)`

```nasm
abs64:
    test rax, rax
    jns .done                ; jump if not signed (SF=0)
    neg rax
.done:
    ret
```

## Conditional moves (`cmovcc`)

Branchless alternative to short if/else. Faster when the branch is unpredictable.

```nasm
    cmp rax, rbx
    mov rcx, rax
    cmovl rcx, rbx           ; rcx = min(rax, rbx)
```

## Short vs near vs far

NASM picks the encoding automatically. To force a size you can write `jmp short .x` or `jmp near .x`; you rarely need to.

## Pitfalls

- A conditional jump after an instruction that doesn't update flags will use **stale** flags. Always pair it with a flag-setting instruction.
- `inc`/`dec` leave CF untouched — don't use them just before `jc`/`jnc`.

## Next

- [Loops](13-loops.md)
