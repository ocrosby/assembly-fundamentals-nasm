# Linux Syscalls — Sockets & Networking

Calls that create sockets, establish connections, and move data across them.
Load the number into `rax`, place arguments in `rdi, rsi, rdx, r10, r8, r9`,
then `syscall`. See the [reference hub](README.md) for the register convention.

| Name          | Number (`rax`) | Args                          | Purpose                             |
|---------------|----------------|-------------------------------|-------------------------------------|
| `socket`      | 41             | domain, type, protocol        | create a socket, return an fd       |
| `connect`     | 42             | fd, addr, addrlen             | connect to a peer                   |
| `bind`        | 49             | fd, addr, addrlen             | bind a socket to an address         |
| `listen`      | 50             | fd, backlog                   | mark a socket as accepting          |
| `accept`      | 43             | fd, addr, addrlen             | accept a connection, return an fd   |
| `accept4`     | 288            | fd, addr, addrlen, flags      | `accept` with flags                 |
| `sendto`      | 44             | fd, buf, len, flags, to, tolen| send a datagram or message          |
| `recvfrom`    | 45             | fd, buf, len, flags, from, fromlen | receive a datagram or message  |
| `sendmsg`     | 46             | fd, msg, flags                | send via a message header           |
| `recvmsg`     | 47             | fd, msg, flags                | receive via a message header        |
| `getsockname` | 51             | fd, addr, addrlen             | read a socket's local address       |
| `getpeername` | 52             | fd, addr, addrlen             | read a socket's peer address        |
| `getsockopt`  | 55             | fd, level, name, val, len     | read a socket option                |
| `setsockopt`  | 54             | fd, level, name, val, len     | set a socket option                 |
| `shutdown`    | 48             | fd, how                       | shut down part of a connection      |
| `socketpair`  | 53             | domain, type, protocol, sv    | create a connected socket pair      |

## See also

- [Reference hub](README.md)
- [Process & execution](process.md)
