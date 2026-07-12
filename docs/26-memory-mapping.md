# Memory Mapping

`mmap` and `munmap` give a program bulk virtual memory outside its
`.bss` — anonymous scratch pages, file-backed views, and shared-memory
IPC across `fork`, all through one syscall pair. This chapter walks
the three flag combinations the runnable examples in
[`examples/30-shared-mapping`](../examples/30-shared-mapping/),
[`examples/31-mmap-file`](../examples/31-mmap-file/), and
[`examples/32-mmap-shared`](../examples/32-mmap-shared/) introduce.

## The syscall

```
mmap(addr, len, prot, flags, fd, offset)  → address or -errno
munmap(addr, len)                          → 0 or -errno
```

`mmap` is a six-argument BSD syscall — the fourth argument (`flags`)
has to move from System V's `rcx` slot to the kernel's `r10` slot
before the `syscall` instruction. `libs/io/libio.a` handles that in
its wrapper; direct callers use `SYSCALL_ARG4` from
`libs/io/syscall/syscall.inc`.

`prot` and `flags` are OR-ed bitmasks. The interesting flag values
appear on both platforms with the same numbers:

| Constant    | Value  | Meaning                                 |
|-------------|--------|-----------------------------------------|
| `PROT_READ` | 1      | Page is readable.                       |
| `PROT_WRITE`| 2      | Page is writable.                       |
| `PROT_EXEC` | 4      | Page is executable.                     |
| `MAP_SHARED`| 1      | Changes reach other mappers / the file. |
| `MAP_PRIVATE`| 2     | Changes stay in this process (COW).     |
| `MAP_FIXED` | 0x10   | Force `addr` to be used exactly.        |

`MAP_ANON` is the exception — Darwin picks `0x1000`, Linux picks
`0x20`. `syscall.inc` collapses that behind a single name; consumers
write `MAP_ANON | MAP_PRIVATE` uniformly.

## Combination 1 — anonymous private scratch page

`fd = -1`, `MAP_ANON | MAP_PRIVATE`. The kernel hands back a
zero-filled page owned by the calling process alone.

```nasm
xor edi, edi                    ; addr = NULL
mov esi, 4096                   ; len = one page
mov edx, PROT_READ | PROT_WRITE
mov ecx, MAP_ANON | MAP_PRIVATE
mov r8d, -1                     ; fd (unused for anonymous)
xor r9d, r9d                    ; offset = 0
call mmap
```

Uses: a large scratch buffer that outlives `.bss`, a stack for a
future thread, any allocation whose size the linker can't compute at
build time. See [`30-shared-mapping`](../examples/30-shared-mapping/).

## Combination 2 — file-backed private view

Drop `MAP_ANON`, pass a real `fd` and `offset`. The kernel backs the
mapping with the file's contents; reads through the pointer return
the file's bytes, and `PROT_WRITE` writes would live in a private
copy on demand.

```nasm
; Set the fd size first — reads past EOF SIGBUS on Linux.
mov edi, fd
mov rsi, 4096
call ftruncate

; Then map read-only, private.
xor edi, edi
mov esi, 4096
mov edx, PROT_READ
mov ecx, MAP_PRIVATE
mov r8d, fd
xor r9d, r9d
call mmap
```

macOS zero-fills the mapping's tail past EOF; Linux raises `SIGBUS`.
Depending on that difference is a portability trap — always size the
file first with `ftruncate`. See
[`31-mmap-file`](../examples/31-mmap-file/).

## Combination 3 — shared page across `fork`

Same anonymous mapping as combination 1, but with `MAP_SHARED`
instead of `MAP_PRIVATE`. After `fork` the parent and child both hold
the same kernel object — writes through either process's pointer are
visible to the other.

```nasm
; Parent
xor edi, edi
mov esi, 4096
mov edx, PROT_READ | PROT_WRITE
mov ecx, MAP_SHARED | MAP_ANON
mov r8d, -1
xor r9d, r9d
call mmap
mov rbx, rax                    ; page address; survives fork

call fork
test rax, rax
jz .child

; Parent: wait4 the child, then read what it wrote.
; Child:  mov byte [rbx], 42; _exit(0)
```

`wait4` is what guarantees the child's store has completed before the
parent reads — do the read after the reap, not before. See
[`32-mmap-shared`](../examples/32-mmap-shared/).

## Releasing the mapping

`munmap(addr, len)` returns the pages to the kernel; subsequent
access to any page in that range raises `SIGSEGV` until the space is
mapped again.

```nasm
mov rdi, rbx                    ; address returned by mmap
mov esi, 4096                   ; same length
call munmap
```

Pass the exact `addr` and `len` that `mmap` returned; storing both in
a caller-side struct is cheaper than trying to recover them later.

## See also

- [`39-growable-buffer.md`](39-growable-buffer.md) — libbuf,
  the mmap-backed byte vector one level up from this
  chapter's raw primitive: `struct buf` bookkeeping, the
  `max(cap*2, needed)` grow strategy, and the pointer
  relocation that falls out of `mmap` + `memcpy` +
  `munmap` on both platforms.

## Next

- Back to [docs/README.md](README.md).
