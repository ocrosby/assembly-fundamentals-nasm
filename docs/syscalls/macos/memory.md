# macOS Syscalls — Memory Management

Calls that map, protect, and lock regions of the address space, plus the
shared-memory object interface. Load the `rax` value shown, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for how the `rax` value is formed.

| Name         | Base | `rax` value | Args                              | Purpose                             |
|--------------|------|-------------|-----------------------------------|-------------------------------------|
| `mmap`       | 197  | `0x20000c5` | addr, len, prot, flags, fd, offset| map files or anonymous memory       |
| `munmap`     | 73   | `0x2000049` | addr, len                         | unmap a region                      |
| `mprotect`   | 74   | `0x200004a` | addr, len, prot                   | change protection of a region       |
| `madvise`    | 75   | `0x200004b` | addr, len, advice                 | advise the kernel on usage          |
| `msync`      | 65   | `0x2000041` | addr, len, flags                  | flush a mapping to its backing store|
| `mincore`    | 78   | `0x200004e` | addr, len, vec                    | report which pages are resident     |
| `mlock`      | 203  | `0x20000cb` | addr, len                         | lock pages into memory              |
| `munlock`    | 204  | `0x20000cc` | addr, len                         | unlock pages                        |
| `minherit`   | 250  | `0x20000fa` | addr, len, inherit                | set inheritance across `fork`       |
| `shm_open`   | 266  | `0x200010a` | name, oflag, mode                 | open a shared-memory object         |
| `shm_unlink` | 267  | `0x200010b` | name                              | remove a shared-memory object       |

## See also

- [Reference hub](README.md)
- [Signals, time & resources](signals-time.md)
