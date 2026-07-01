# Linux Syscalls — File Descriptors & I/O

Calls that operate on open file descriptors: reading, writing, seeking,
duplicating, and multiplexing. Load the number into `rax`, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for the register convention.

| Name        | Number (`rax`) | Args                     | Purpose                                |
|-------------|----------------|--------------------------|----------------------------------------|
| `read`      | 0              | fd, buf, count           | read bytes from a descriptor           |
| `write`     | 1              | fd, buf, count           | write bytes to a descriptor            |
| `open`      | 2              | path, flags, mode        | open or create a file, return an fd    |
| `openat`    | 257            | dirfd, path, flags, mode | open relative to a directory fd        |
| `close`     | 3              | fd                       | close a descriptor                     |
| `lseek`     | 8              | fd, offset, whence       | reposition the file offset             |
| `dup`       | 32             | fd                       | duplicate a descriptor                 |
| `dup2`      | 33             | oldfd, newfd             | duplicate onto a specific descriptor   |
| `pipe`      | 22             | pipefd                   | create a pipe (returns two fds)        |
| `pipe2`     | 293            | pipefd, flags            | create a pipe with flags               |
| `fcntl`     | 72             | fd, cmd, arg             | control descriptor attributes          |
| `ioctl`     | 16             | fd, request, arg         | device-specific control                |
| `pread64`   | 17             | fd, buf, count, offset   | read at an offset without seeking      |
| `pwrite64`  | 18             | fd, buf, count, offset   | write at an offset without seeking     |
| `readv`     | 19             | fd, iov, iovcnt          | scatter-read into multiple buffers     |
| `writev`    | 20             | fd, iov, iovcnt          | gather-write from multiple buffers     |
| `fsync`     | 74             | fd                       | flush file data and metadata to disk   |
| `fdatasync` | 75             | fd                       | flush file data to disk                |
| `poll`      | 7              | fds, nfds, timeout       | wait for events on a set of fds        |
| `ppoll`     | 271            | fds, nfds, tmo, sigmask  | `poll` with a signal mask and timespec |
| `select`    | 23             | nfds, readfds, writefds, exceptfds, timeout | wait on fd sets       |
| `flock`     | 73             | fd, operation            | apply or remove an advisory lock       |
| `truncate`  | 76             | path, length             | set a file's length by path            |
| `ftruncate` | 77             | fd, length               | set a file's length by descriptor      |

## See also

- [Reference hub](README.md)
- [Filesystem & metadata](filesystem.md)
