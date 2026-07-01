# macOS Syscalls — Sockets & Networking

Calls that create sockets, establish connections, and move data across them.
Load the `rax` value shown, place arguments in `rdi, rsi, rdx, r10, r8, r9`,
then `syscall`. See the [reference hub](README.md) for how the `rax`
value is formed.

| Name          | Base | `rax` value | Args                          | Purpose                             |
|---------------|------|-------------|-------------------------------|-------------------------------------|
| `socket`      | 97   | `0x2000061` | domain, type, protocol        | create a socket, return an fd       |
| `connect`     | 98   | `0x2000062` | fd, addr, addrlen             | connect to a peer                   |
| `bind`        | 104  | `0x2000068` | fd, addr, addrlen             | bind a socket to an address         |
| `listen`      | 106  | `0x200006a` | fd, backlog                   | mark a socket as accepting          |
| `accept`      | 30   | `0x200001e` | fd, addr, addrlen             | accept a connection, return an fd   |
| `sendto`      | 133  | `0x2000085` | fd, buf, len, flags, to, tolen| send a datagram or message          |
| `recvfrom`    | 29   | `0x200001d` | fd, buf, len, flags, from, fromlen | receive a datagram or message  |
| `sendmsg`     | 28   | `0x200001c` | fd, msg, flags                | send via a message header           |
| `recvmsg`     | 27   | `0x200001b` | fd, msg, flags                | receive via a message header        |
| `getsockname` | 32   | `0x2000020` | fd, addr, addrlen             | read a socket's local address       |
| `getpeername` | 31   | `0x200001f` | fd, addr, addrlen             | read a socket's peer address        |
| `getsockopt`  | 118  | `0x2000076` | fd, level, name, val, len     | read a socket option                |
| `setsockopt`  | 105  | `0x2000069` | fd, level, name, val, len     | set a socket option                 |
| `shutdown`    | 134  | `0x2000086` | fd, how                       | shut down part of a connection      |
| `socketpair`  | 135  | `0x2000087` | domain, type, protocol, sv    | create a connected socket pair      |

## See also

- [Reference hub](README.md)
- [Process & execution](process.md)
