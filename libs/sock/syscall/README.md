# libs/sock/syscall/

Kernel-syscall wrappers for the
[`<sys/socket.h>`](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/sys_socket.h.html)
family, plus the shared `syscall.inc` header they all rely on.
Every file in this directory is a thin shim: load the syscall
number, hand control to the kernel, normalize the error
convention on return.

For consumer-facing documentation of the archive as a whole
(build, link line, calling convention, TCP-client example) see
[`../README.md`](../README.md).

## Contents

### Connection lifecycle

| File            | Symbol     | Purpose                                              |
| --------------- | ---------- | ---------------------------------------------------- |
| `socket.asm`    | `socket`   | Create an endpoint of communication.                 |
| `bind.asm`      | `bind`     | Assign a local address to a socket.                  |
| `listen.asm`    | `listen`   | Mark a bound socket as passive.                      |
| `accept.asm`    | `accept`   | Dequeue a completed connection, returning a new fd.  |
| `connect.asm`   | `connect`  | Initiate a connection to a peer.                     |
| `shutdown.asm`  | `shutdown` | Disable send and/or receive on a connected socket.   |
| `close.asm`     | `close`    | Release the fd (triggers TCP close handshake).       |

### I/O

| File            | Symbol      | Purpose                                                        |
| --------------- | ----------- | -------------------------------------------------------------- |
| `read.asm`      | `read`      | Read bytes from an fd.                                         |
| `write.asm`     | `write`     | Write bytes to an fd.                                          |
| `send.asm`      | `send`      | Send on a connected socket (delegates to `sendto` NULL addr).  |
| `recv.asm`      | `recv`      | Receive on a connected socket (delegates to `recvfrom`).       |
| `sendto.asm`    | `sendto`    | Send to a specific address — datagram sockets, or explicit.    |
| `recvfrom.asm`  | `recvfrom`  | Receive and capture the sender's address.                      |
| `sendmsg.asm`   | `sendmsg`   | Scatter-send with ancillary data via `struct msghdr`.          |
| `recvmsg.asm`   | `recvmsg`   | Gather-receive with ancillary data via `struct msghdr`.        |

### Options and introspection

| File               | Symbol         | Purpose                                              |
| ------------------ | -------------- | ---------------------------------------------------- |
| `getsockopt.asm`   | `getsockopt`   | Read a per-socket option (SO_ERROR, TCP_NODELAY, …). |
| `setsockopt.asm`   | `setsockopt`   | Set a per-socket option (SO_REUSEADDR, SO_RCVTIMEO). |
| `getsockname.asm`  | `getsockname`  | Report the local address a socket is bound to.       |
| `getpeername.asm`  | `getpeername`  | Report the address a socket is connected to.         |
| `socketpair.asm`   | `socketpair`   | Create a pre-connected AF_UNIX fd pair for IPC.      |

### Multiplexing

| File          | Symbol   | Purpose                                                       |
| ------------- | -------- | ------------------------------------------------------------- |
| `select.asm`  | `select` | Wait for readiness on three `fd_set` bitmaps plus a timeval.  |
| `poll.asm`    | `poll`   | Wait for events on a `struct pollfd` array with ms timeout.   |

## Shared header

`syscall.inc` centralizes three things every wrapper needs:

- **Per-platform `SYS_*` numbers.** macOS BSD-class syscalls
  carry the `0x2000000` prefix (drawn from `<sys/syscall.h>` in
  the Xcode command-line SDK); Linux uses the plain x86-64
  numbers from `<asm/unistd_64.h>`. Both branches sit behind
  `%ifdef MACOS`, so a single archive built for either platform
  picks up the right constants.
- **`SYSCALL_NORM` macro.** Runs `syscall`, then on macOS
  converts the BSD carry-flag error convention (`CF=1`, positive
  errno in `rax`) to Linux's `-errno` shape. On Linux the macro
  is just `syscall`. This is what makes every wrapper's contract
  identical on both platforms: non-negative on success, negative
  errno on failure.
- **`SYSCALL_ARG4` macro.** Moves `rcx` into `r10` before the
  syscall. The System V AMD64 ABI passes the 4th argument in
  `rcx`, but the `syscall` instruction clobbers `rcx` (it holds
  the return address), so the kernel's ABI expects the 4th
  argument in `r10` instead. Wrappers with four or more
  arguments — `send`, `recv`, `sendto`, `recvfrom`, `getsockopt`,
  `setsockopt`, `select`, `socketpair` — invoke `SYSCALL_ARG4`
  before `SYSCALL_NORM`.

## Wrapper shape

Every file in this directory follows the same short template:

```nasm
%include "syscall.inc"

default rel

global <symbol>

section .text

<symbol>:
    SYSCALL_ARG4                    ; only for 4+ arg wrappers
    mov rax, SYS_<name>
    SYSCALL_NORM
    ret
```

The uniformity is deliberate. It keeps the taxonomy easy to
skim, forecloses per-wrapper divergence in error handling, and
localizes every syscall number to `syscall.inc` — so a new
platform is one file, not twenty-two.

## Build

The parent [`../Makefile`](../Makefile) invokes NASM with
`-I syscall/` for every file in this directory so
`%include "syscall.inc"` resolves regardless of the working
directory make was launched from. The `.o` files are declared to
depend on `syscall.inc`, so editing the shared header rebuilds
every wrapper.
