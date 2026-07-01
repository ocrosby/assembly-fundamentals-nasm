# gdb Walkthrough

A step-by-step tour of debugging a small NASM program under `gdb` on
Linux. The target is [`examples/07-square`](../examples/07-square/) —
the same program the [lldb Walkthrough](23-lldb-walkthrough.md) uses
on macOS, so the two chapters can be read side by side to compare
the debuggers.

For the reference-level `gdb` command list, see
[Debugging](19-debugging.md). This chapter is the walkthrough.

## Setup

Build the target with DWARF debug info:

```bash
cd examples/07-square
make clean
nasm -f elf64 -g -F dwarf square.asm -o square.o
ld square.o -o square
gdb ./square
```

Linux `ld` defaults to `_start` as the entry symbol, which is one of
the two globals `examples/07-square` declares — no `-e` flag needed.

## Switch to Intel syntax

`gdb` defaults to AT&T output for disassembly. NASM sources are in
Intel syntax, so match:

```
(gdb) set disassembly-flavor intel
```

Add the same line to `~/.gdbinit` if you want it always on.

## Break at `_start`

```
(gdb) break _start
Breakpoint 1 at 0x4000b0
(gdb) run
Starting program: .../square

Breakpoint 1, 0x00000000004000b0 in _start ()
```

`gdb` pauses just before the first instruction of `_start`. Registers
hold whatever the kernel and the ELF loader left in them:

```
(gdb) info registers rdi rax rsp
rdi            0x0                 0
rax            0x0                 0
rsp            0x7fffffffe410      0x7fffffffe410
```

## Step to the `call`

Step one machine instruction at a time with `stepi` (short: `si`):

```
(gdb) stepi                          ; past `mov rdi, 7`
(gdb) info registers rdi
rdi            0x7                 7
```

The next instruction is `call square`. Step into it:

```
(gdb) stepi
0x00000000004000ba in square ()
```

`gdb` now reports the current frame as `square` — we are inside the
function.

## Inspect the callee

Disassemble the current function to see the body:

```
(gdb) disassemble
Dump of assembler code for function square:
=> 0x00000000004000ba <+0>: mov  rax,rdi
   0x00000000004000bd <+3>: imul rax,rdi
   0x00000000004000c1 <+7>: ret
End of assembler dump.
```

The `=>` arrow marks the next instruction to execute. Step through
the two arithmetic ops:

```
(gdb) stepi                          ; mov rax, rdi
(gdb) info registers rax
rax            0x7                 7        ; x

(gdb) stepi                          ; imul rax, rdi
(gdb) info registers rax
rax            0x31                49       ; = 7 * 7
```

`0x31` is `49` in decimal — the correct square. One more `stepi`
returns to the caller:

```
(gdb) stepi                          ; ret
0x00000000004000b7 in _start ()
```

## Watch the exit status flow

Back in `_start`, the next instruction is `mov rdi, rax`, which
copies the result into arg 1 for `sys_exit`:

```
(gdb) stepi
(gdb) info registers rdi
rdi            0x31                49       ; passed to sys_exit
```

Let the program finish:

```
(gdb) continue
Continuing.
[Inferior 1 (process ...) exited with code 061]
```

`code 061` is octal for decimal `49` — `gdb` prints the exit status
in octal. It matches `rax` at the moment `syscall` issued `sys_exit`.

## Inspect the stack across a `call`

Break at `_start` again, step past `call square`, and look at what
`call` pushed:

```
(gdb) x/4gx $rsp
0x7fffffffe3f8: 0x00000000004000a1  0x0000000000000000
0x7fffffffe408: 0x0000000000000000  0x0000000000000000
```

`x/4gx` means "examine 4 giant (8-byte) hex words at `$rsp`". The
word at `$rsp` is the return address — the location in `_start` that
follows the `call`. `ret` will pop this into `rip`.

## Handy shortcuts

| Long form                | Short   |
|--------------------------|---------|
| `stepi`                  | `si`    |
| `nexti`                  | `ni`    |
| `break SYM`              | `b SYM` |
| `info registers`         | `i r`   |
| `disassemble`            | `disas` |
| `continue`               | `c`     |
| `print/x $rax`           | `p/x $rax` |
| `quit`                   | `q`     |

## TUI mode

`gdb` ships with a terminal UI that shows the source, registers, and
disassembly in split panes:

```
(gdb) layout asm       ; disassembly pane
(gdb) layout regs      ; adds a register pane
(gdb) tui disable      ; back to the plain prompt
```

## See also

- [lldb Walkthrough](23-lldb-walkthrough.md) — the macOS counterpart.
- [Debugging](19-debugging.md) — reference-level `lldb` and `gdb` commands.
- [Procedures](14-procedures.md) — the calling convention this walkthrough follows.
- [The Stack](15-stack.md) — what `call` and `ret` do to `rsp`.
- [Index](README.md)
