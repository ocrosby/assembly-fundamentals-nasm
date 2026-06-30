# Data Movement

Moving bytes around is most of what assembly does. Five instructions cover almost everything.

## `mov` — copy

```nasm
    mov rax, 10              ; immediate  -> register
    mov rax, rbx             ; register   -> register
    mov rax, [buf]           ; memory     -> register
    mov [buf], rax           ; register   -> memory
```

`mov` cannot copy memory-to-memory in a single instruction — go through a register.

## `lea` — compute an address

Loads the *effective address* of an operand rather than its contents.

```nasm
    lea rsi, [msg]           ; rsi = &msg
    lea rax, [rbx + rcx*8]   ; rax = rbx + rcx*8 (arithmetic shortcut)
```

## `xchg` — swap two operands

```nasm
    xchg rax, rbx            ; swap
```

`xchg` with a memory operand carries an implicit `lock` prefix — useful for atomics, slow otherwise.

## `push` and `pop` — stack moves

```nasm
    push rax                 ; rsp -= 8; [rsp] = rax
    pop rbx                  ; rbx = [rsp]; rsp += 8
```

The stack grows **downward**. See [The Stack](15-stack.md).

## Sign and zero extension

When moving a smaller value into a larger register, choose explicitly:

```nasm
    movzx rax, byte [buf]    ; zero-extend  (unsigned)
    movsx rax, byte [buf]    ; sign-extend  (signed)
    movsxd rax, dword [buf]  ; 32 -> 64 sign-extend
```

A bare `mov eax, ...` already zero-extends into `rax`, which is the common case.

## Next

- [Arithmetic](09-arithmetic.md)
