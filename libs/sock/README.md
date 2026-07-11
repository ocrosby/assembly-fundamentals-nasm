# libs/sock/

Berkeley sockets primitives packaged as the static archive
`libsock.a`. Every routine is a direct syscall wrapper — no libc,
no libSystem call, no allocation.

See [`../README.md`](../README.md) for the conventions shared by
every archive in `libs/`.

Wrappers are added group by group; see the individual `.asm`
files for the exported symbols and the shared
[`syscall.inc`](syscall.inc) for per-platform `SYS_*` numbers and
the `SYSCALL_NORM` / `SYSCALL_ARG4` macros.
