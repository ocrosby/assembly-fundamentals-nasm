# Loops

Loops are written by hand from a label and a conditional jump.

## The canonical pattern

```nasm
    mov rcx, 10
.loop: ; ... body uses rcx ...
    dec rcx
    jnz .loop
```

This counts down because comparing to zero is one instruction (`dec` updates ZF) instead of two.

## Counting up

```nasm
    xor rcx, rcx
.loop:
    cmp rcx, 10
    jge .done
    ; ... body ...
    inc rcx
    jmp .loop
.done:
```

## `loop` instruction

`loop label` is shorthand for `dec rcx; jnz label`. It uses `rcx` implicitly and is slower than the manual form on modern CPUs — prefer the explicit pattern above for performance, use `loop` only for brevity in small examples.

```nasm
    mov rcx, 10
.again: ; ... body ...
    loop .again
```

## Iterating an array

```nasm
section .data
arr: dq 10, 20, 30, 40, 50
arr_len: equ ($ - arr) / 8

section .text
sum_arr:
    xor rax, rax             ; sum
    xor rcx, rcx             ; index
    lea rbx, [arr]           ; base ptr (RIP-relative)
.next:
    cmp rcx, arr_len
    jge .done
    add rax, [rbx + rcx*8]
    inc rcx
    jmp .next
.done:
    ret
```

## String operations and `rep`

`rep` repeats a string instruction `rcx` times. Common pairings:

```nasm
    ; memcpy(rdi, rsi, rcx)
    cld
    rep movsb                ; copies rcx bytes
    ; memset(rdi, al, rcx)
    rep stosb
```

`cld` clears DF so the pointers advance forward; `std` makes them go backward.

## Runnable

- [examples/05-countdown/](../examples/05-countdown/) — the `dec`/`jnz` idiom.
- [examples/06-sum-array/](../examples/06-sum-array/) — the array-sum loop above as
  a complete program. `make && make run`.

## Next

- [Procedures](14-procedures.md)
