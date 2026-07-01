# References

External sources to go deeper than these guides.

## NASM

- [NASM home](https://www.nasm.us/) — downloads and release notes.
- [NASM manual](https://www.nasm.us/doc/) — the assembler's reference, including the preprocessor and every directive.

## Instruction set

- [Felix Cloutier's x86 reference](https://www.felixcloutier.com/x86/) — fast HTML index of every x86-64 instruction, derived from Intel's Software Developer's Manual.
- [OSDev wiki — x86-64](https://wiki.osdev.org/X86-64) — concise overviews of long mode, paging, and CPU state.

## Operating system interface

- [Syscall Reference](syscalls/README.md) — the common macOS and Linux calls, organized by category, with the `rax` value each one needs.
- [XNU `syscalls.master`](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/syscalls.master) — Apple's source-of-truth table that assigns every macOS BSD syscall number.
- [Linux `syscall_64.tbl`](https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl) — the kernel's source-of-truth table that assigns every x86-64 syscall number.
- [Linux x86-64 syscall table (rchapman)](https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/) — number, name, and full argument layout for every Linux syscall.

## See also

- [Index](README.md)
