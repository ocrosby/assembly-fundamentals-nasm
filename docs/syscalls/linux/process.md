# Linux Syscalls — Process & Execution

Calls that create processes, replace a process image, wait for children, and
read or set process identity. Load the number into `rax`, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for the register convention.

| Name         | Number (`rax`) | Args                          | Purpose                              |
|--------------|----------------|-------------------------------|--------------------------------------|
| `exit`       | 60             | status                        | terminate the calling thread         |
| `exit_group` | 231            | status                        | terminate all threads in the process |
| `fork`       | 57             | —                             | create a child process               |
| `vfork`      | 58             | —                             | fork sharing the address space        |
| `clone`      | 56             | flags, stack, ptid, ctid, tls | create a process or thread            |
| `execve`     | 59             | path, argv, envp              | replace the process image            |
| `wait4`      | 61             | pid, status, options, rusage  | wait for a child, collect status     |
| `waitid`     | 247            | idtype, id, infop, options, rusage | wait with finer child selection |
| `getpid`     | 39             | —                             | process ID of the caller             |
| `getppid`    | 110            | —                             | parent process ID                    |
| `kill`       | 62             | pid, sig                      | send a signal to a process           |
| `getuid`     | 102            | —                             | real user ID                         |
| `geteuid`    | 107            | —                             | effective user ID                    |
| `getgid`     | 104            | —                             | real group ID                        |
| `getegid`    | 108            | —                             | effective group ID                   |
| `setuid`     | 105            | uid                           | set the user ID                      |
| `setgid`     | 106            | gid                           | set the group ID                     |
| `setsid`     | 112            | —                             | start a new session                  |
| `setpgid`    | 109            | pid, pgid                     | set a process group                  |
| `getpgrp`    | 111            | —                             | process-group ID                     |
| `umask`      | 95             | mask                          | set the file-mode creation mask      |
| `ptrace`     | 101            | request, pid, addr, data      | trace or control another process     |

## See also

- [Reference hub](README.md)
- [File descriptors & I/O](file-io.md)
