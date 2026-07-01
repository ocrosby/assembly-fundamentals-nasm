# Linux Syscalls — Signals, Time & Resources

Calls that install and mask signal handlers, read and set clocks and timers, and
query resource usage and limits. Load the number into `rax`, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for the register convention.

| Name             | Number (`rax`) | Args                     | Purpose                               |
|------------------|----------------|--------------------------|---------------------------------------|
| `rt_sigaction`   | 13             | sig, act, oact, sigsetsize| install a signal handler             |
| `rt_sigprocmask` | 14             | how, set, oset, sigsetsize| change the blocked-signal mask       |
| `rt_sigpending`  | 127            | set, sigsetsize          | report pending signals                |
| `rt_sigsuspend`  | 130            | mask, sigsetsize         | wait for a signal with a temp mask    |
| `sigaltstack`    | 131            | ss, oss                  | set the alternate signal stack        |
| `rt_sigreturn`   | 15             | —                        | return from a signal handler          |
| `kill`           | 62             | pid, sig                 | send a signal (see Process page)      |
| `nanosleep`      | 35             | req, rem                 | sleep for a relative interval         |
| `clock_gettime`  | 228            | clockid, tp              | read a specified clock                |
| `clock_nanosleep`| 230            | clockid, flags, req, rem | sleep against a specified clock       |
| `gettimeofday`   | 96             | tv, tz                   | read the wall clock                   |
| `settimeofday`   | 164            | tv, tz                   | set the wall clock                    |
| `getitimer`      | 36             | which, value             | read an interval timer                |
| `setitimer`      | 38             | which, value, ovalue     | arm an interval timer                 |
| `getrusage`      | 98             | who, usage               | report resource usage                 |
| `getrlimit`      | 97             | resource, rlim           | read a resource limit                 |
| `setrlimit`      | 160            | resource, rlim           | set a resource limit                  |
| `prlimit64`      | 302            | pid, resource, new, old  | read or set a limit (modern form)     |
| `getrandom`      | 318            | buf, buflen, flags       | fill a buffer with random bytes       |

## See also

- [Reference hub](README.md)
- [Sockets & networking](network.md)
