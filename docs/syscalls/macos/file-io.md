# macOS Syscalls — File Descriptors & I/O

Calls that operate on open file descriptors: reading, writing, seeking,
duplicating, and multiplexing. Load the `rax` value shown, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for how the `rax` value is formed.

| Name        | Base | `rax` value | Args                     | Purpose                                |
|-------------|------|-------------|--------------------------|----------------------------------------|
| `read`      | 3    | `0x2000003` | fd, buf, count           | read bytes from a descriptor           |
| `write`     | 4    | `0x2000004` | fd, buf, count           | write bytes to a descriptor            |
| `open`      | 5    | `0x2000005` | path, flags, mode        | open or create a file, return an fd    |
| `close`     | 6    | `0x2000006` | fd                       | close a descriptor                     |
| `lseek`     | 199  | `0x20000c7` | fd, offset, whence       | reposition the file offset             |
| `dup`       | 41   | `0x2000029` | fd                       | duplicate a descriptor                 |
| `dup2`      | 90   | `0x200005a` | oldfd, newfd             | duplicate onto a specific descriptor   |
| `pipe`      | 42   | `0x200002a` | fildes                   | create a pipe (returns two fds)        |
| `fcntl`     | 92   | `0x200005c` | fd, cmd, arg             | control descriptor attributes          |
| `ioctl`     | 54   | `0x2000036` | fd, request, arg         | device-specific control                |
| `pread`     | 153  | `0x2000099` | fd, buf, count, offset   | read at an offset without seeking      |
| `pwrite`    | 154  | `0x200009a` | fd, buf, count, offset   | write at an offset without seeking     |
| `readv`     | 120  | `0x2000078` | fd, iov, iovcnt          | scatter-read into multiple buffers     |
| `writev`    | 121  | `0x2000079` | fd, iov, iovcnt          | gather-write from multiple buffers     |
| `fsync`     | 95   | `0x200005f` | fd                       | flush file data and metadata to disk   |
| `fdatasync` | 187  | `0x20000bb` | fd                       | flush file data to disk                |
| `poll`      | 230  | `0x20000e6` | fds, nfds, timeout       | wait for events on a set of fds        |
| `select`    | 93   | `0x200005d` | nfds, readfds, writefds, errorfds, timeout | wait on fd sets       |
| `flock`     | 131  | `0x2000083` | fd, operation            | apply or remove an advisory lock       |
| `truncate`  | 200  | `0x20000c8` | path, length             | set a file's length by path            |
| `ftruncate` | 201  | `0x20000c9` | fd, length               | set a file's length by descriptor      |

## See also

- [Reference hub](README.md)
- [Filesystem & metadata](filesystem.md)
