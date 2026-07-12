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
;   * SYSCALL_NORM (and SYSCALL_ARG4, unused here but
;     available) come from `syscall-common.inc` — every
;     syscall-making archive under `libs/` shares that file.
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

%include "syscall-common.inc"

%ifdef MACOS
%define SYS_gettimeofday 0x2000074
%define SYS_poll         0x20000e6
%define SYS_getrusage    0x2000075
%else
%define SYS_gettimeofday 96
%define SYS_poll         7
%define SYS_getrusage    98
%endif

%define TV_SEC_OFF   0
%define TV_USEC_OFF  8
%define TIMEVAL_SIZE 16

; getrusage(who, rusage*) — who selectors.
%define RUSAGE_SELF      0
%define RUSAGE_CHILDREN  -1

; struct rusage — the two struct timevals we care about here.
; ru_utime and ru_stime are `struct timeval` at fixed offsets,
; identical on both platforms; the remaining fields (page faults,
; context switches, …) differ in width and are not exposed via
; libtime constants.
%define RU_UTIME_OFF 0
%define RU_STIME_OFF 16

%endif
