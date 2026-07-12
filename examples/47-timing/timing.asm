; Measure elapsed wall-clock time across a `sleep_ms(50)`
; call using libtime's `now_ms`. The classic "record now,
; do work, record now again, subtract" pattern that every
; benchmark and every "how long did that take?" log line
; is built on.
;
; First runnable that uses libtime as the *star* rather than
; a supporting cast member. Exits 42 when the observed
; elapsed time lands in the plausible band (40..500ms —
; slack on both ends absorbs scheduler jitter).
;
; Program flow:
;
;   start = now_ms()                       ; wall-clock ms since epoch
;   sleep_ms(50)                            ; nap for ~50ms
;   end   = now_ms()
;   elapsed = end - start
;   assert 40 <= elapsed < 500              ; plausibility band
;   exit(42)
;
; The lower bound is 40ms rather than 50ms because kernel
; scheduling and `poll(NULL, 0, 50)`-side rounding can shave
; a few milliseconds off. The upper bound is 500ms rather
; than 100ms because CI runners under load can stall for a
; while; going strict here would produce flaky red on
; unrelated PRs.

%ifdef MACOS
%define SYS_exit    0x2000001
%else
%define SYS_exit    60
%endif

default rel

extern now_ms, sleep_ms

global _start
global _main

section .text

_start:
_main:
    ; ---- start = now_ms() ----
    call now_ms
    test rax, rax
    js .fail                                ; -errno from gettimeofday
    mov rbx, rax                            ; save start (callee-saved)

    ; ---- sleep_ms(50) ----
    mov edi, 50
    call sleep_ms
    test rax, rax
    jnz .fail

    ; ---- end = now_ms() ----
    call now_ms
    test rax, rax
    js .fail

    ; ---- elapsed = end - start ----
    sub rax, rbx

    ; ---- Verify 40 <= elapsed < 500 ----
    cmp rax, 40
    jl .fail
    cmp rax, 500
    jge .fail

    ; ---- exit(42) ----
    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
