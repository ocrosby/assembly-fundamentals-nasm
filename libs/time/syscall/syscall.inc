; syscall.inc — shared per-platform syscall numbers and macros
;
; Every wrapper in libtime includes this file. It centralizes:
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
;   * TV_SEC_OFF / TV_USEC_OFF / TIMEVAL_SIZE — struct timeval
;     field offsets and total size. On both macOS and Linux the
;     struct is 16 bytes: tv_sec at offset 0 (qword), tv_usec at
;     offset 8. tv_usec is 4 bytes on macOS (suseconds_t is
;     int32_t) and 8 bytes on Linux (suseconds_t is long), but
;     the value itself is always in the range 0..999999 so a
;     32-bit read at offset 8 is safe on both platforms.

%ifndef TIME_SYSCALL_INC
%define TIME_SYSCALL_INC

%ifdef MACOS
%define SYS_gettimeofday 0x2000074
%else
%define SYS_gettimeofday 96
%endif

%define TV_SEC_OFF   0
%define TV_USEC_OFF  8
%define TIMEVAL_SIZE 16

%macro SYSCALL_NORM 0
    syscall
%ifdef MACOS
    jnc %%ok                        ; CF=0 → success
    neg rax                         ; CF=1 → positive errno → -errno
%%ok:
%endif
%endmacro

%endif
