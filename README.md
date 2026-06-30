# assembly-fundamentals-nasm

This repository collects practical assembly language notes for NASM, with small
worked examples, setup guidance, and reference links for studying x86-64
assembly on Linux.

## What this repository covers

- NASM syntax basics
- Linux x86-64 system call conventions
- Registers, memory, and data sections
- Simple arithmetic and control flow examples
- Reference links for deeper study

## NASM program structure

Most NASM programs in Linux are organized around three common sections:

- `.data` for initialized data
- `.bss` for uninitialized storage
- `.text` for executable instructions

Programs also usually expose a global entry point:

```nasm
global _start
```

## Building and running a program

For a 64-bit Linux target, a common NASM workflow is:

```bash
nasm -f elf64 program.asm -o program.o
ld program.o -o program
./program
```

## Example 1: Hello, world

This example writes a string to standard output using the `write` system call
and then exits with the `exit` system call.

```nasm
global _start

section .data
message db "Hello, world!", 10
length  equ $ - message

section .text
_start:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov rsi, message    ; buffer
    mov rdx, length     ; byte count
    syscall

    mov rax, 60         ; sys_exit
    xor rdi, rdi        ; status 0
    syscall
```

## Example 2: Integer addition

This example adds two integers and returns the result as the process exit code.
It demonstrates moving immediate values into registers and using `add`.

```nasm
global _start

section .text
_start:
    mov rax, 7
    mov rbx, 5
    add rax, rbx

    mov rdi, rax        ; exit status = 12
    mov rax, 60         ; sys_exit
    syscall
```

## Example 3: Countdown loop

This example uses a loop counter and `jnz` to repeat until the counter reaches
zero.

```nasm
global _start

section .text
_start:
    mov rcx, 5

countdown:
    dec rcx
    jnz countdown

    mov rax, 60         ; sys_exit
    xor rdi, rdi
    syscall
```

## Core concepts to understand

### Registers

Some important 64-bit general-purpose registers:

- `rax`: often used for return values and syscall numbers
- `rbx`: general-purpose register
- `rcx`: frequently used as a counter
- `rdx`: extra data or syscall argument
- `rsi`: source index or syscall argument
- `rdi`: destination index or syscall argument
- `rsp`: stack pointer
- `rbp`: base pointer for stack frames

### Data movement

- `mov` copies data between registers, memory, and immediates
- `lea` computes addresses without dereferencing memory
- `push` and `pop` move values on and off the stack

### Arithmetic and logic

- `add`, `sub`, `inc`, `dec`
- `imul`, `idiv`
- `and`, `or`, `xor`, `test`, `cmp`

### Control flow

- `jmp` for unconditional jumps
- `je`, `jne`, `jg`, `jl`, `jnz` for conditional jumps
- `call` and `ret` for functions

## Suggested learning path

1. Learn the role of `.data`, `.bss`, and `.text`
2. Practice loading values into registers with `mov`
3. Use arithmetic instructions such as `add` and `sub`
4. Add conditional branches with `cmp` and jump instructions
5. Move on to stack frames, functions, and memory addressing

## Reference links

- [NASM documentation](https://www.nasm.us/doc/)
- [Linux x86-64 syscall table](https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/)
- [x86-64 instruction reference](https://www.felixcloutier.com/x86/)
- [OSDev wiki: x86-64](https://wiki.osdev.org/X86-64)
