; syscall.inc — shared per-platform syscall numbers and macros
;
; Every wrapper in libsock includes this file. It centralizes:
;
;   * The SYS_* syscall numbers, resolved differently per platform.
;     macOS BSD-class syscalls carry the 0x2000000 class prefix
;     (drawn from <sys/syscall.h> in the Xcode command-line SDK).
;     Linux uses the plain x86-64 syscall numbers from
;     <asm/unistd_64.h>.
;
;   * SYSCALL_NORM and SYSCALL_ARG4 macros come from
;     `syscall-common.inc` — every syscall-making archive
;     under `libs/` shares that file so the macros only
;     have to change in one place.

%ifndef SOCK_SYSCALL_INC
%define SOCK_SYSCALL_INC

%include "syscall-common.inc"

%ifdef MACOS
%define SYS_read        0x2000003
%define SYS_write       0x2000004
%define SYS_close       0x2000006
%define SYS_recvmsg     0x200001b
%define SYS_sendmsg     0x200001c
%define SYS_recvfrom    0x200001d
%define SYS_accept      0x200001e
%define SYS_getpeername 0x200001f
%define SYS_getsockname 0x2000020
%define SYS_select      0x200005d
%define SYS_socket      0x2000061
%define SYS_connect     0x2000062
%define SYS_bind        0x2000068
%define SYS_setsockopt  0x2000069
%define SYS_listen      0x200006a
%define SYS_getsockopt  0x2000076
%define SYS_sendto      0x2000085
%define SYS_shutdown    0x2000086
%define SYS_socketpair  0x2000087
%define SYS_poll        0x20000e6
%else
%define SYS_read        0
%define SYS_write       1
%define SYS_close       3
%define SYS_poll        7
%define SYS_select      23
%define SYS_socket      41
%define SYS_connect     42
%define SYS_accept      43
%define SYS_sendto      44
%define SYS_recvfrom    45
%define SYS_sendmsg     46
%define SYS_recvmsg     47
%define SYS_shutdown    48
%define SYS_bind        49
%define SYS_listen      50
%define SYS_getsockname 51
%define SYS_getpeername 52
%define SYS_socketpair  53
%define SYS_setsockopt  54
%define SYS_getsockopt  55
%endif

; -----------------------------------------------------------------
; v1.1: shared socket-domain constants.
;
; The individual syscall wrappers don't need these (they just
; forward the caller's register values to the kernel), but composed
; helpers in util/ do — and hardcoding them privately in each
; helper is how drift creeps in. Every value below matches the
; platform's <sys/socket.h> / <netinet/in.h> headers.
;
; Address families:
%define AF_INET      2
%ifdef MACOS
%define AF_INET6     30
%else
%define AF_INET6     10
%endif

; Socket types are consistent across BSD-derived Unixes:
%define SOCK_STREAM  1
%define SOCK_DGRAM   2

; SIN_HEADER is the first two bytes of `struct sockaddr_in` for an
; AF_INET socket, packed as a little-endian u16 that a `mov word`
; can drop into the first slot of the struct.
;
; On BSD-derived Unixes (macOS included) `struct sockaddr_in`
; starts with `sin_len` (u8) then `sin_family` (u8); the AF_INET
; value with sin_len=16 gives 0x0210 when read as a little-endian
; u16. Linux does not carry the length byte — the family sits at
; offset 0 as a u16, so SIN_HEADER on Linux is just AF_INET.
%ifdef MACOS
%define SIN_HEADER   0x0210
%else
%define SIN_HEADER   0x0002
%endif

; SOL_SOCKET is the option "level" for socket-level options
; (SO_REUSEADDR, SO_TYPE, SO_RCVTIMEO, …). One of the earliest
; surprises between the two ABIs: macOS reuses the historical BSD
; sentinel 0xffff, Linux picked 1.
%ifdef MACOS
%define SOL_SOCKET   0xffff
%define SO_REUSEADDR 0x0004
%define SO_TYPE      0x1008
%define SO_RCVTIMEO  0x1006
%define SO_SNDTIMEO  0x1005
%else
%define SOL_SOCKET   1
%define SO_REUSEADDR 2
%define SO_TYPE      3
%define SO_RCVTIMEO  20
%define SO_SNDTIMEO  21
%endif

%endif ; SOCK_SYSCALL_INC
