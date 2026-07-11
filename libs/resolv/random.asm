; resolv_random(buf: rdi, len: rsi) -> rax = 0 or negative errno
;
; Fills *buf* with *len* cryptographically-random bytes drawn
; from the kernel's entropy pool. macOS's getentropy takes
; (buf, len) and Linux's getrandom takes (buf, len, flags) — we
; pass flags = 0 on Linux so the syscall blocks if the pool is
; still initializing rather than failing early.
;
; The DNS query ID needs to be unpredictable to a network
; attacker; using /dev/urandom via open+read would work too but
; would drag in a filesystem dependency for the common case.
; The direct syscall is cleaner.

%include "syscall.inc"

default rel

global resolv_random

section .text

resolv_random:
%ifdef MACOS
    mov rax, SYS_getentropy
%else
    ; Linux getrandom(buf, len, flags). We pass flags=0.
    xor edx, edx
    mov rax, SYS_getrandom
%endif
    SYSCALL_NORM
    ret
