; now_ms(void) -> rax = wall-clock milliseconds since Unix epoch
;                       (or negative errno if gettimeofday failed)
;
; Convenience wrapper that composes gettimeofday + a
; single-precision millisecond conversion into one call. The
; return is a signed 64-bit integer suitable for log
; timestamps, benchmark deltas, and any other consumer that
; wants "wall-clock time as a number" without touching a
; `struct timeval`.
;
; No arguments.
;
; Return:
;   rax >= 0   milliseconds since 1970-01-01 UTC. Fits in
;              signed 64 bits until year 292 million something.
;   rax  < 0   -errno propagated from gettimeofday. Failures
;              are exceedingly rare (the wrapper never fails
;              on a healthy kernel) but the wrapper still
;              respects the archive's negative-return
;              convention.
;
; Precision: this is milliseconds derived from
; gettimeofday's microsecond precision, so the returned value
; steps in 1 ms increments and is subject to the same wall-
; clock caveats — NTP jumps, DST transitions, manual clock
; adjustments. For elapsed-time measurements pin two calls
; close together and subtract.
;
; Stack layout during the syscall:
;   [rsp + 0..15]  struct timeval scratch
;   entry rsp mod 16 = 8; `sub rsp, 24` lands at mod 16 = 0
;   which keeps the nested `call gettimeofday` aligned.

%include "syscall.inc"

default rel

extern gettimeofday

global now_ms

section .text

now_ms:
    sub rsp, 24                     ; 16 for tv + 8 alignment pad

    lea rdi, [rsp]
    xor esi, esi                    ; tz = NULL
    call gettimeofday
    test rax, rax
    js .done                        ; propagate -errno

    ; ms = tv_sec * 1000 + tv_usec / 1000
    mov r8,  [rsp + TV_SEC_OFF]
    mov rax, 1000
    imul r8, rax                    ; r8 = tv_sec * 1000

    mov eax, [rsp + TV_USEC_OFF]    ; tv_usec (< 1_000_000, fits in u32)
    xor edx, edx
    mov ecx, 1000
    div ecx                         ; eax = tv_usec / 1000

    add rax, r8                     ; combine

.done:
    add rsp, 24
    ret
