# The Stack

`rsp` points to the top of a downward-growing stack of 8-byte slots.

## Push and pop

```nasm
    push rax                 ; rsp -= 8; [rsp] = rax
    pop rbx                  ; rbx = [rsp]; rsp += 8
```

## Reserving local space

To make room for N bytes of locals, subtract from `rsp`:

```nasm
    sub rsp, 32              ; 32 bytes of scratch space
    mov qword [rsp + 0], rdi
    mov qword [rsp + 8], rsi
    ; ... use ...
    add rsp, 32              ; release before ret
```

Always release exactly what you reserved. Imbalanced `rsp` corrupts the return address.

## The classic frame pointer prologue/epilogue

Useful when locals are accessed by name through `rbp`, and required by some debuggers for clean stack traces:

```nasm
my_func:
    push rbp                 ; save caller's frame ptr
    mov rbp, rsp             ; new frame
    sub rsp, 32              ; locals
    ; ... body uses [rbp - 8], [rbp - 16] ...
    mov rsp, rbp             ; release locals
    pop rbp
    ret
```

## Alignment rule

Across a `call`, `rsp` must be 16-byte aligned **before** the call instruction executes. Inside the callee (after the implicit push of the return address), `rsp` is therefore 8 mod 16. The first `push rbp` of the prologue restores 16-byte alignment.

If you `call` external code without a prologue, align manually:

```nasm
    sub rsp, 8               ; re-align to 16
    call puts
    add rsp, 8
```

## Pitfalls

- Forgetting to balance `push`/`pop` is the #1 cause of mysterious segfaults at `ret`.
- Calling into `libc` from a misaligned stack often crashes inside SIMD code.
- The red zone (128 bytes below `rsp`) is yours to scribble in leaf functions; the OS will not clobber it.

## Next

- [System Calls](16-system-calls.md)
