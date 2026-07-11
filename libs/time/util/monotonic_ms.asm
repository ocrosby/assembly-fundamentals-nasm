; monotonic_ms(void) -> rax = monotonic milliseconds, or -ENOSYS
;                       on macOS
;
; The best a "no libc" archive can do for monotonic time.
; This helper is deliberately asymmetric — a rare exception
; to libtime's "same shape on both platforms or not shipped"
; discipline:
;
;   Linux:  clock_gettime(CLOCK_MONOTONIC, &ts) via SYS 228,
;           returns tv_sec * 1000 + tv_nsec / 1_000_000. The
;           value is milliseconds since some monotonic origin
;           the kernel chooses at boot; only differences
;           between two calls are meaningful.
;   macOS:  returns -ENOSYS (-78, `ENOSYS` on Darwin). The
;           raw-syscall path to Darwin's monotonic clock was
;           closed off in modern macOS — SYS_clock_gettime_nsec_np
;           (462) returns -1 to userspace (verified on Darwin
;           25.3), and mach_absolute_time via the mach trap
;           returns a value in an unstable, undocumented unit.
;           The only routes are the commpage (version-fragile
;           addresses) or libSystem (banned by the archive's
;           no-libc policy).
;
; The asymmetric result is honest: callers on macOS get an
; unmistakable -ENOSYS they can detect and fall back to
; whatever wall-clock or mach-trap approach fits their
; tolerance. A wrapper that silently returned gettimeofday-
; derived milliseconds on macOS would be lying about
; monotonicity, and this file refuses to lie.
;
; No arguments.
;
; Return:
;   rax >= 0  monotonic milliseconds (Linux only).
;   rax  < 0  -errno. On macOS the value is always -ENOSYS
;             (-78). On Linux, any errno the kernel returns
;             from clock_gettime propagates unchanged.
;
; Stack layout (Linux only):
;   [rsp + 0..15]  struct timespec { tv_sec, tv_nsec }
;   entry rsp mod 16 = 8; `sub rsp, 24` lands at mod 16 = 0
;   which keeps the (leaf) syscall aligned.

default rel

global monotonic_ms

section .text

%ifdef MACOS

; ENOSYS on macOS is 78; we return the negated value so
; callers see the same "-errno on failure" convention every
; other libtime routine uses.
monotonic_ms:
    mov rax, -78
    ret

%else

%define SYS_clock_gettime  228
%define CLOCK_MONOTONIC    1

; struct timespec layout on x86_64 Linux:
;   +0  time_t tv_sec (8 bytes)
;   +8  long   tv_nsec (8 bytes)
%define TS_SEC_OFF   0
%define TS_NSEC_OFF  8
%define TIMESPEC_SIZE 16

monotonic_ms:
    sub rsp, 24                     ; 16-byte timespec + 8 pad, aligned

    mov edi, CLOCK_MONOTONIC
    lea rsi, [rsp]                  ; &ts
    mov rax, SYS_clock_gettime
    syscall
    test rax, rax
    js .done                        ; -errno straight through

    ; ms = tv_sec * 1000 + tv_nsec / 1_000_000
    mov r8, [rsp + TS_SEC_OFF]
    mov rax, 1000
    imul r8, rax

    mov rax, [rsp + TS_NSEC_OFF]
    xor edx, edx
    mov rcx, 1000000
    div rcx                         ; rax = tv_nsec / 1_000_000

    add rax, r8

.done:
    add rsp, 24
    ret

%endif
