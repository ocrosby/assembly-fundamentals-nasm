# Syscall Reference

Category-organized lists of the system calls you are most likely to invoke
directly from x86-64 assembly, with the number to load into `rax` and the
argument layout for each. Both platforms share the register convention
(`rdi, rsi, rdx, r10, r8, r9`; negative `rax` is `-errno`), covered in
[System Calls](../16-system-calls.md); they differ in how the number in `rax`
is formed and in the numbers themselves.

## Platforms

- [macOS](macos/README.md) — BSD calls. The number is the base OR-ed with the `0x2000000` (class 2) prefix; Apple treats these as unstable.
- [Linux](linux/README.md) — x86-64 table. The number goes into `rax` directly and is a stable ABI.

Windows is not covered: it is not a build target of this project (WSL2 counts as
Linux), and its NT syscall numbers are undocumented and change between releases.
On Windows you call the Win32 API or `ntdll` exports rather than raw syscalls.

## See also

- [System Calls](../16-system-calls.md) — the register convention and the macOS-vs-Linux overview.
- [References](../21-references.md) — external syscall tables and manuals.
- [Index](../README.md)
