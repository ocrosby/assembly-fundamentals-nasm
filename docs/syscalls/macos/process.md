# macOS Syscalls — Process & Execution

Calls that create processes, replace a process image, wait for children, and
read or set process identity. Load the `rax` value shown, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for how the `rax` value is formed.

| Name          | Base | `rax` value | Args                          | Purpose                              |
|---------------|------|-------------|-------------------------------|--------------------------------------|
| `exit`        | 1    | `0x2000001` | status                        | terminate the calling process        |
| `fork`        | 2    | `0x2000002` | —                             | create a child process               |
| `vfork`       | 66   | `0x2000042` | —                             | fork sharing the address space        |
| `execve`      | 59   | `0x200003b` | path, argv, envp              | replace the process image            |
| `posix_spawn` | 244  | `0x20000f4` | pid, path, actions, attr, argv, envp | fork+exec in one call         |
| `wait4`       | 7    | `0x2000007` | pid, status, options, rusage  | wait for a child, collect status     |
| `waitid`      | 173  | `0x20000ad` | idtype, id, infop, options    | wait with finer child selection      |
| `getpid`      | 20   | `0x2000014` | —                             | process ID of the caller             |
| `getppid`     | 39   | `0x2000027` | —                             | parent process ID                    |
| `kill`        | 37   | `0x2000025` | pid, sig                      | send a signal to a process           |
| `getuid`      | 24   | `0x2000018` | —                             | real user ID                         |
| `geteuid`     | 25   | `0x2000019` | —                             | effective user ID                    |
| `getgid`      | 47   | `0x200002f` | —                             | real group ID                        |
| `getegid`     | 43   | `0x200002b` | —                             | effective group ID                   |
| `setuid`      | 23   | `0x2000017` | uid                           | set the user ID                      |
| `setgid`      | 181  | `0x20000b5` | gid                           | set the group ID                     |
| `setsid`      | 147  | `0x2000093` | —                             | start a new session                  |
| `setpgid`     | 82   | `0x2000052` | pid, pgid                     | set a process group                  |
| `getpgrp`     | 81   | `0x2000051` | —                             | process-group ID                     |
| `umask`       | 60   | `0x200003c` | mask                          | set the file-mode creation mask      |
| `ptrace`      | 26   | `0x200001a` | request, pid, addr, data      | trace or control another process     |

## See also

- [Reference hub](README.md)
- [File descriptors & I/O](file-io.md)
