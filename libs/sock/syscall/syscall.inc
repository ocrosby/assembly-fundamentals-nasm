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
;   * SYSCALL_NORM — normalizes the macOS carry-flag error
;     convention to Linux's "negative errno in rax" convention, so
;     every wrapper returns non-negative on success and a negative
;     errno on failure regardless of platform.
;
;   * SYSCALL_ARG4 — the System V AMD64 ABI passes the 4th
;     argument in rcx, but the kernel's syscall ABI clobbers rcx
;     (it holds the return address) and expects the 4th arg in r10.
;     Wrappers with four or more arguments must translate rcx→r10
;     before invoking the syscall.

%ifndef SOCK_SYSCALL_INC
%define SOCK_SYSCALL_INC

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

%macro SYSCALL_NORM 0
    syscall
%ifdef MACOS
    jnc %%ok                        ; CF=0 → success
    neg rax                         ; CF=1 → positive errno → -errno
%%ok:
%endif
%endmacro

%macro SYSCALL_ARG4 0
    mov r10, rcx                    ; 4th arg: SysV rcx → syscall r10
%endmacro

%endif ; SOCK_SYSCALL_INC
