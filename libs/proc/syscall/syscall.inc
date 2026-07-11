; syscall.inc — shared per-platform syscall numbers and macros
; for libproc.
;
; Every wrapper in libproc includes this file. macOS BSD-class
; syscalls carry the 0x2000000 class prefix (from
; <sys/syscall.h> in the Xcode command-line SDK); Linux uses
; the plain x86-64 numbers from <asm/unistd_64.h>.
;
; SYSCALL_NORM normalizes the macOS carry-flag error convention
; to Linux's "negative errno in rax" convention, so every
; wrapper returns non-negative on success and a negative errno
; on failure regardless of platform.
;
; SYSCALL_ARG4 is here because wait4 is 4-arg — the System V
; AMD64 ABI passes arg 4 in rcx, but the kernel's syscall ABI
; clobbers rcx (return address of the syscall instruction) and
; expects arg 4 in r10.

%ifndef PROC_SYSCALL_INC
%define PROC_SYSCALL_INC

%ifdef MACOS
%define SYS_fork    0x2000002
%define SYS_wait4   0x2000007
%define SYS_getpid  0x2000014
%define SYS_kill    0x2000025
%define SYS_getppid 0x2000027
%define SYS_execve  0x200003b
%define SYS_exit    0x2000001
%else
%define SYS_fork    57
%define SYS_wait4   61
%define SYS_getpid  39
%define SYS_kill    62
%define SYS_getppid 110
%define SYS_execve  59
%define SYS_exit    60
%endif

; wait4 `options` flags — bitwise-OR'd. WNOHANG returns 0
; immediately if no child has exited; WUNTRACED / WCONTINUED
; deliver stop/continue notifications the caller then decodes
; with W_STOPSIG / W_CONTSIG. Values match between platforms.
%define WNOHANG    1
%define WUNTRACED  2

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

%endif
