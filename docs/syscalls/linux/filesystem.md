# Linux Syscalls — Filesystem & Metadata

Calls that inspect and change files and directories by path: status, ownership,
permissions, links, and extended attributes. Load the number into `rax`, place
arguments in `rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for the register convention.

| Name         | Number (`rax`) | Args                          | Purpose                              |
|--------------|----------------|-------------------------------|--------------------------------------|
| `stat`       | 4              | path, statbuf                 | file status by path                  |
| `fstat`      | 5              | fd, statbuf                   | file status by descriptor            |
| `lstat`      | 6              | path, statbuf                 | file status without following a link |
| `newfstatat` | 262            | dirfd, path, statbuf, flags   | status relative to a directory fd    |
| `access`     | 21             | path, mode                    | check accessibility of a path        |
| `faccessat`  | 269            | dirfd, path, mode             | `access` relative to a directory fd  |
| `chmod`      | 90             | path, mode                    | change permission bits by path       |
| `fchmod`     | 91             | fd, mode                      | change permission bits by descriptor |
| `chown`      | 92             | path, owner, group            | change ownership by path             |
| `fchown`     | 93             | fd, owner, group              | change ownership by descriptor       |
| `link`       | 86             | oldpath, newpath              | create a hard link                   |
| `unlink`     | 87             | path                          | remove a directory entry             |
| `unlinkat`   | 263            | dirfd, path, flags            | remove relative to a directory fd    |
| `symlink`    | 88             | target, linkpath              | create a symbolic link               |
| `readlink`   | 89             | path, buf, bufsize            | read a symbolic link's target        |
| `rename`     | 82             | oldpath, newpath              | rename a file or directory           |
| `renameat`   | 264            | olddirfd, old, newdirfd, new  | rename relative to directory fds     |
| `mkdir`      | 83             | path, mode                    | create a directory                   |
| `rmdir`      | 84             | path                          | remove an empty directory            |
| `chdir`      | 80             | path                          | change the working directory         |
| `fchdir`     | 81             | fd                            | change the working directory by fd   |
| `getdents64` | 217            | fd, dirent, count             | read directory entries               |
| `mknod`      | 133            | path, mode, dev               | create a special or ordinary file    |
| `utimensat`  | 280            | dirfd, path, times, flags     | set access and modification times    |
| `statfs`     | 137            | path, buf                     | file-system statistics by path       |
| `getxattr`   | 191            | path, name, value, size       | read an extended attribute           |
| `setxattr`   | 188            | path, name, value, size, flags| write an extended attribute          |

## See also

- [Reference hub](README.md)
- [Memory management](memory.md)
