# macOS Syscalls — Filesystem & Metadata

Calls that inspect and change files and directories by path: status, ownership,
permissions, links, and extended attributes. Load the `rax` value shown, place
arguments in `rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for how the `rax` value is formed.

| Name            | Base | `rax` value | Args                   | Purpose                              |
|-----------------|------|-------------|------------------------|--------------------------------------|
| `stat`          | 188  | `0x20000bc` | path, buf              | file status by path                  |
| `fstat`         | 189  | `0x20000bd` | fd, buf                | file status by descriptor            |
| `lstat`         | 190  | `0x20000be` | path, buf              | file status without following a link |
| `access`        | 33   | `0x2000021` | path, mode             | check accessibility of a path        |
| `chmod`         | 15   | `0x200000f` | path, mode             | change permission bits by path       |
| `fchmod`        | 124  | `0x200007c` | fd, mode               | change permission bits by descriptor |
| `chown`         | 16   | `0x2000010` | path, owner, group     | change ownership by path             |
| `fchown`        | 123  | `0x200007b` | fd, owner, group       | change ownership by descriptor       |
| `link`          | 9    | `0x2000009` | path1, path2           | create a hard link                   |
| `unlink`        | 10   | `0x200000a` | path                   | remove a directory entry             |
| `symlink`       | 57   | `0x2000039` | path1, path2           | create a symbolic link               |
| `readlink`      | 58   | `0x200003a` | path, buf, bufsize     | read a symbolic link's target        |
| `rename`        | 128  | `0x2000080` | from, to               | rename a file or directory           |
| `mkdir`         | 136  | `0x2000088` | path, mode             | create a directory                   |
| `rmdir`         | 137  | `0x2000089` | path                   | remove an empty directory            |
| `chdir`         | 12   | `0x200000c` | path                   | change the working directory         |
| `fchdir`        | 13   | `0x200000d` | fd                     | change the working directory by fd   |
| `getdirentries` | 196  | `0x20000c4` | fd, buf, count, basep  | read directory entries               |
| `mkfifo`        | 132  | `0x2000084` | path, mode             | create a named pipe                  |
| `utimes`        | 138  | `0x200008a` | path, times            | set access and modification times    |
| `statfs`        | 157  | `0x200009d` | path, buf              | file-system statistics by path       |
| `getxattr`      | 234  | `0x20000ea` | path, name, value, size, position, options | read an extended attribute |
| `setxattr`      | 236  | `0x20000ec` | path, name, value, size, position, options | write an extended attribute |
| `pathconf`      | 191  | `0x20000bf` | path, name             | query a configurable path limit      |

## See also

- [Reference hub](README.md)
- [Memory management](memory.md)
