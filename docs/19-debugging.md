# Debugging

Step through your program, inspect registers, and find the line where things went wrong.

## Assemble with debug info

```bash
nasm -f macho64 -g -F dwarf hello.asm -o hello.o   # macOS
nasm -f elf64   -g -F dwarf hello.asm -o hello.o   # Linux
ld hello.o -o hello
```

`-g -F dwarf` embeds source-line information so the debugger can map instructions back to your `.asm` file.

## `lldb` (macOS) — minimum useful session

```bash
lldb ./hello
```

```
(lldb) breakpoint set --name _main
(lldb) run
(lldb) register read
(lldb) memory read --size 1 --count 16 --format x &msg
(lldb) thread step-inst
(lldb) continue
(lldb) quit
```

## `gdb` (Linux) — equivalent session

```bash
gdb ./hello
```

```
(gdb) break _start          # set a breakpoint
(gdb) run                   # start the program
(gdb) layout asm            # show disassembly window
(gdb) layout regs           # show registers window
(gdb) stepi                 # step one instruction
(gdb) info registers        # dump all GPRs
(gdb) x/16xb &msg           # examine 16 bytes at msg
(gdb) print/x $rax          # print rax in hex
(gdb) continue              # run to next breakpoint
(gdb) quit
```

Switch to Intel syntax once per session:

```
(gdb) set disassembly-flavor intel
```

## Quick checks without a debugger

```bash
file ./hello                # binary type
strings ./hello             # any literals embedded?
nm ./hello | grep ' T '     # what code symbols exist?
```

## Common failure modes

| Symptom                   | First thing to check                              |
|---------------------------|---------------------------------------------------|
| Segfault on `ret`         | `rsp` imbalance — count your pushes/pops          |
| Segfault inside a `call`  | Stack not 16-byte aligned at the call             |
| Wrong arithmetic result   | Operand size mismatch; review `mov` widths        |
| Garbage in a register     | Caller-saved register clobbered across a `call`   |

## Next

- [Cheat Sheet](20-cheat-sheet.md)
