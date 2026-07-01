# macOS Syscalls — Signals, Time & Resources

Calls that install and mask signal handlers, read and set clocks and timers, and
query resource usage and limits. Load the `rax` value shown, place arguments in
`rdi, rsi, rdx, r10, r8, r9`, then `syscall`. See the
[reference hub](README.md) for how the `rax` value is formed.

| Name           | Base | `rax` value | Args                   | Purpose                               |
|----------------|------|-------------|------------------------|---------------------------------------|
| `sigaction`    | 46   | `0x200002e` | sig, act, oact         | install a signal handler              |
| `sigprocmask`  | 48   | `0x2000030` | how, set, oset         | change the blocked-signal mask        |
| `sigpending`   | 52   | `0x2000034` | set                    | report pending signals                |
| `sigsuspend`   | 111  | `0x200006f` | mask                   | wait for a signal with a temp mask    |
| `sigaltstack`  | 53   | `0x2000035` | ss, oss                | set the alternate signal stack        |
| `sigreturn`    | 184  | `0x20000b8` | ctx, infostyle, token  | return from a signal handler          |
| `kill`         | 37   | `0x2000025` | pid, sig               | send a signal (see Process page)      |
| `gettimeofday` | 116  | `0x2000074` | tp, tzp                | read the wall clock                   |
| `settimeofday` | 122  | `0x200007a` | tp, tzp                | set the wall clock                    |
| `getitimer`    | 86   | `0x2000056` | which, value           | read an interval timer                |
| `setitimer`    | 83   | `0x2000053` | which, value, ovalue   | arm an interval timer                 |
| `getrusage`    | 117  | `0x2000075` | who, rusage            | report resource usage                 |
| `getrlimit`    | 194  | `0x20000c2` | resource, rlp          | read a resource limit                 |
| `setrlimit`    | 195  | `0x20000c3` | resource, rlp          | set a resource limit                  |
| `getentropy`   | 500  | `0x20001f4` | buf, buflen            | fill a buffer with random bytes       |

## See also

- [Reference hub](README.md)
- [Sockets & networking](network.md)
