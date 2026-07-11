; syscall.inc — shared per-platform syscall numbers and macros
;
; Every wrapper in libio includes this file. It centralizes:
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
;     errno on failure regardless of platform. On Linux the macro
;     is just `syscall` because the kernel already writes -errno
;     into rax.
;
;   * SYSCALL_ARG4 — the System V AMD64 ABI passes the 4th
;     argument in rcx, but the kernel's syscall ABI clobbers rcx
;     (it holds the return address) and expects the 4th arg in
;     r10. Wrappers with four or more arguments must translate
;     rcx→r10 before invoking the syscall.
;
; libio and libsock ship duplicate copies of these macros so each
; archive stays self-contained. If a third archive lands with the
; same pattern the shared definitions should promote to a
; libs/-level include.

%ifndef LIBIO_SYSCALL_INC
%define LIBIO_SYSCALL_INC

%ifdef MACOS
%define SYS_open   0x2000005
%define SYS_pread  0x2000099
%define SYS_pwrite 0x200009a
%define SYS_lseek  0x20000c7
%define SYS_openat 0x20001cf
%else
%define SYS_open   2
%define SYS_lseek  8
%define SYS_pread  17
%define SYS_pwrite 18
%define SYS_openat 257
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

%endif ; LIBIO_SYSCALL_INC
