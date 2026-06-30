# Cheat Sheet

One-page reference. Each row links to the chapter that explains it.

## Build

```bash
nasm -f elf64   -g -F dwarf  file.asm -o file.o   # Linux
nasm -f macho64 -g -F dwarf  file.asm -o file.o   # macOS
ld file.o -o file                                  # Linux
clang file.o -o file                               # macOS (links libSystem)
```

See [Linking](18-linking.md).

## Register quick view

`rax rbx rcx rdx rsi rdi rbp rsp r8 r9 r10 r11 r12 r13 r14 r15`

Args (SysV): `rdi rsi rdx rcx r8 r9` · Return: `rax` · Callee-saved: `rbx rbp r12–r15` — see [Registers](04-registers.md).

## Data widths

`db dw dd dq` (init) · `resb resw resd resq` (uninit) — see [Data Types](06-data-types.md).

## Move and address

```nasm
mov  rax, rbx       ; copy
lea  rax, [rbx+8]   ; address arithmetic
xchg rax, rbx       ; swap
push rax / pop rbx  ; stack
```

See [Data Movement](08-data-movement.md).

## Arithmetic

```nasm
add  sub  inc  dec  neg
imul rax, rbx
xor  rdx, rdx ; before unsigned div
div  rcx      ; rax / rcx, rem in rdx
```

See [Arithmetic](09-arithmetic.md).

## Logic and shifts

```nasm
and or xor not
shl shr sar     ; logical / arithmetic
rol ror         ; rotates
test rax, rax   ; ZF if zero
```

See [Bitwise & Shifts](10-bitwise.md).

## Control flow

```nasm
cmp rax, rbx
je jne jl jle jg jge      ; signed
jb jbe ja jae             ; unsigned
jmp label
call proc / ret
```

See [Comparison & Flags](11-comparison.md), [Jumps](12-jumps.md), [Procedures](14-procedures.md).

## Syscalls

| Platform | `rax` for `write` | `rax` for `exit` |
|----------|-------------------|------------------|
| Linux    | `1`               | `60`             |
| macOS    | `0x2000004`       | `0x2000001`      |

See [System Calls](16-system-calls.md).

## Idioms

```nasm
xor  rax, rax       ; zero a register
test rax, rax       ; flag-set without modifying it
sub  rsp, 8         ; re-align stack before a libc call
default rel         ; RIP-relative addressing for PIE
```
