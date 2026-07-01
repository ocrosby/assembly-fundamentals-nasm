# lldb Walkthrough

A step-by-step tour of debugging a small NASM program under `lldb` on
macOS. The target is [`examples/07-square`](../examples/07-square/),
which is small enough to step through end-to-end, and rich enough to
show a `call`, a `ret`, and a return value flowing back through the
System V AMD64 ABI. For the Linux counterpart, see
[gdb Walkthrough](24-gdb-walkthrough.md) — same target, same flow.

For the reference-level `lldb` command list, see
[Debugging](19-debugging.md). This chapter is the walkthrough.

## Setup

Build the target with DWARF debug info:

```bash
cd examples/07-square
make clean
nasm -f macho64 -DMACOS -g -F dwarf square.asm -o square.o
ld -macos_version_min 11.0 -lSystem \
   -syslibroot "$(xcrun -sdk macosx --show-sdk-path)" \
   -o square square.o
lldb ./square
```

**Apple Silicon note.** x86-64 Mach-O binaries run under Rosetta.
Breakpoint resolution on symbol names can be flaky when the debugger
is arm64 and the process is x86_64 translated; run `lldb` through
`arch -x86_64 lldb ./square` in that case. On Intel macs the plain
`lldb ./square` above is sufficient.

## Break at `_main`

```
(lldb) breakpoint set --name _main
Breakpoint 1: where = square`_main, address = 0x1000002e8
(lldb) run
Process ... stopped
* thread #1, stop reason = breakpoint 1.1
    frame #0: square`_main
```

lldb pauses just before the first instruction of `_main`. Registers
hold whatever the dyld startup left in them:

```
(lldb) register read rdi rax rsp
     rdi = 0x0000000000000000
     rax = 0x0000000000000000
     rsp = 0x00007ff7bfeff640
```

## Step to the `call`

Step one machine instruction at a time with `si`:

```
(lldb) si                           ; past `mov rdi, 7`
(lldb) register read rdi
     rdi = 0x0000000000000007
```

The next instruction is `call square`. Step into it:

```
(lldb) si
* thread #1, stop reason = instruction step into
    frame #0: square`square
```

`frame #0` now shows we are inside the `square` function.

## Inspect the callee

Disassemble the current frame to see the function body:

```
(lldb) disassemble --frame
square`square:
->  0x1000002fc: mov  rax, rdi
    0x1000002ff: imul rax, rdi
    0x100000303: ret
```

The arrow marks the next instruction to execute. Step through the
two arithmetic ops:

```
(lldb) si                           ; mov rax, rdi
(lldb) register read rax
     rax = 0x0000000000000007       ; x

(lldb) si                           ; imul rax, rdi
(lldb) register read rax
     rax = 0x0000000000000031       ; = 49 = 7 * 7
```

`0x31` is `49` in decimal — the correct square. One more `si` returns
to the caller:

```
(lldb) si                           ; ret
* frame #0: square`_main
```

## Watch the exit status flow

Back in `_main`, the next instruction is `mov rdi, rax`, which copies
the result into arg 1 for `sys_exit`:

```
(lldb) si
(lldb) register read rdi
     rdi = 0x0000000000000031       ; 49 passed to sys_exit
```

Let the program finish:

```
(lldb) continue
Process ... exited with status = 49 (0x31)
```

The exit status matches the value of `rax` at the moment `syscall`
issued `sys_exit`.

## Inspect the stack across a `call`

Break at `_main` again, step past `call square`, and look at what
`call` pushed:

```
(lldb) memory read --size 8 --count 4 --format x $rsp
0x7ff7bfeff620: 0x00000001000002ed
0x7ff7bfeff628: 0x0000000000000000
...
```

The word at `$rsp` is the return address — the location of the
instruction in `_main` that follows the `call`. `ret` will pop this
into `rip`.

## Handy shortcuts

| Long form                          | Short   |
|------------------------------------|---------|
| `thread step-inst`                 | `si`    |
| `thread step-over`                 | `n`     |
| `breakpoint set --name SYM`        | `b SYM` |
| `register read`                    | `re r`  |
| `continue`                         | `c`     |
| `quit`                             | `q`     |

## See also

- [gdb Walkthrough](24-gdb-walkthrough.md) — the Linux counterpart.
- [Debugging](19-debugging.md) — reference-level `lldb` and `gdb` commands.
- [Procedures](14-procedures.md) — the calling convention this walkthrough follows.
- [The Stack](15-stack.md) — what `call` and `ret` do to `rsp`.
- [Index](README.md)
