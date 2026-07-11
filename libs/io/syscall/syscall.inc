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
; v1.1: metadata + namespace ops.
; SYS_fstat here is Darwin's 64-bit-inode variant
; (fstat64 = BSD syscall 339). The older SYS_fstat (189)
; returns a struct with 32-bit inode numbers that macOS
; deprecated once wide inodes shipped, so libio wraps the
; wider one.
%define SYS_unlink 0x200000a
%define SYS_mkdir  0x2000088
%define SYS_rmdir  0x2000089
%define SYS_fstat  0x2000153
%else
%define SYS_open   2
%define SYS_lseek  8
%define SYS_pread  17
%define SYS_pwrite 18
%define SYS_openat 257
; v1.1 additions on Linux. SYS_fstat = 5 already returns the
; 64-bit stat struct on x86_64, so no fstat64 syscall exists.
%define SYS_unlink 87
%define SYS_mkdir  83
%define SYS_rmdir  84
%define SYS_fstat  5
%endif

; The stat struct is 144 bytes on both macOS (`struct stat64`)
; and Linux (`struct stat` on x86_64), but the field offsets
; differ. Wrappers keep the buffer opaque; util/io-size.asm
; uses ST_SIZE_OFF internally to pull the file size out
; portably. Callers that want other fields should add a
; matching offset here rather than hardcoding it at the call
; site.
%define STATBUF_SIZE 144
%ifdef MACOS
; struct stat64: st_dev(4) st_mode(2) st_nlink(2) st_ino(8)
; st_uid(4) st_gid(4) st_rdev(4) pad(4) atime(16) mtime(16)
; ctime(16) birthtime(16) → st_size at +96.
%define ST_SIZE_OFF  96
%else
; struct stat: st_dev(8) st_ino(8) st_nlink(8) st_mode(4)
; st_uid(4) st_gid(4) pad(4) st_rdev(8) → st_size at +48.
%define ST_SIZE_OFF  48
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
