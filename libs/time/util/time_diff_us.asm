; time_diff_us(late, early) -> rax = (late - early) in microseconds
;
; Pure computation — no syscall, no allocation. Given pointers
; to two `struct timeval`s, return their signed difference in
; microseconds as a 64-bit integer.
;
; Arguments:
;   rdi = late*   pointer to a struct timeval
;   rsi = early*  pointer to a struct timeval
;
; Return:
;   rax = signed microsecond delta
;         positive if late > early (the usual measurement case)
;         zero     if late == early
;         negative if the caller reversed the arguments (a
;                  useful sentinel for benchmark harnesses that
;                  want to detect obvious mistakes)
;
; The layout assumption — tv_sec at offset 0 (qword), tv_usec
; at offset 8 (a 32-bit value in both platforms' effective
; storage) — is shared with `gettimeofday.asm` and documented
; in the archive's syscall.inc.
;
; No overflow guard: 2^63 microseconds is ~292,471 years. If
; the caller manages to feed this two timevals that far apart,
; a wrap around zero is the least of their problems.

%include "syscall.inc"

default rel

global time_diff_us

section .text

time_diff_us:
    ; delta_sec = late.tv_sec - early.tv_sec (signed 64-bit)
    mov rax, [rdi + TV_SEC_OFF]
    sub rax, [rsi + TV_SEC_OFF]

    ; delta_sec_us = delta_sec * 1_000_000
    mov rcx, 1000000
    imul rax, rcx

    ; delta_usec = late.tv_usec - early.tv_usec (32-bit signed)
    mov edx, [rdi + TV_USEC_OFF]
    sub edx, [rsi + TV_USEC_OFF]
    movsxd rdx, edx                 ; sign-extend to 64 bits

    add rax, rdx
    ret
