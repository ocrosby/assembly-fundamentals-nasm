# Linux Syscalls — Memory Management

Calls that adjust the program break and map, protect, and lock regions of the
address space. Load the number into `rax`, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for the register convention.

| Name           | Number (`rax`) | Args                              | Purpose                             |
|----------------|----------------|-----------------------------------|-------------------------------------|
| `brk`          | 12             | addr                              | set the program break               |
| `mmap`         | 9              | addr, len, prot, flags, fd, offset| map files or anonymous memory       |
| `munmap`       | 11             | addr, len                         | unmap a region                      |
| `mprotect`     | 10             | addr, len, prot                   | change protection of a region       |
| `madvise`      | 28             | addr, len, advice                 | advise the kernel on usage          |
| `msync`        | 26             | addr, len, flags                  | flush a mapping to its backing store|
| `mincore`      | 27             | addr, len, vec                    | report which pages are resident     |
| `mlock`        | 149            | addr, len                         | lock pages into memory              |
| `munlock`      | 150            | addr, len                         | unlock pages                        |
| `memfd_create` | 319            | name, flags                       | create an anonymous memory-backed fd|

## See also

- [Reference hub](README.md)
- [Signals, time & resources](signals-time.md)
