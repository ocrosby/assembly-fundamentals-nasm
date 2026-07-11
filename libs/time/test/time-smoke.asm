; time-smoke.asm — v1.0 gettimeofday coverage plus v1.1
; sleep_ms and getrusage coverage.
;
; Standalone. Sub-check ids:
;
; v1.0 — gettimeofday plausibility and monotonicity:
;   1  gettimeofday(&tv1, NULL) → 0
;   2  tv1.tv_sec >= 1_700_000_000   (November 2023 epoch — proves
;                                     the wrapper actually filled
;                                     the struct rather than
;                                     silently returning 0)
;   3  tv1.tv_usec < 1_000_000       (valid microsecond range)
;   4  gettimeofday(&tv2, NULL) → 0
;   5  tv2 >= tv1                    (never goes backward within
;                                     the same process — a
;                                     sanity check against
;                                     wrapper-side struct
;                                     scribbling)
;   6  (tv2.tv_sec - tv1.tv_sec) < 10 (guard against the wrapper
;                                     accidentally storing an
;                                     enormous value)
;
; v1.1 — sleep_ms actually sleeps:
;   7  gettimeofday(&tv3, NULL) → 0
;   8  sleep_ms(50) → 0
;   9  gettimeofday(&tv4, NULL) → 0
;   A  (tv4 - tv3) in microseconds >= 40_000 (allow scheduler
;                                     slack; if we got back
;                                     under 40ms the sleep
;                                     silently no-op'd)
;   B  (tv4 - tv3) in microseconds < 2_000_000 (upper sanity
;                                     bound — should be well
;                                     under 2s even on a
;                                     loaded runner)
;
; v1.1 — getrusage returns a plausible struct:
;   C  getrusage(RUSAGE_SELF, &ru) → 0
;   D  ru.ru_utime.tv_sec >= 0 AND ru.ru_utime.tv_usec >= 0
;      (proves the wrapper wrote a valid timeval — 0 is fine on
;      a fast process where the accumulated user CPU has been
;      microseconds so far, but negative would mean the wrapper
;      scribbled something outside the buffer)
;
; v1.2 — time_diff_us pure-computation helper:
;   E  time_diff_us(&tv4, &tv3) >= 40_000  (same 50ms sleep,
;                                          expressed via the
;                                          util helper)
;   F  time_diff_us(&tv3, &tv4) < 0        (reversed args → negative)
;
; v1.3 — now_ms util helper:
;   G  now_ms() >= 1_700_000_000_000       (Nov 2023 in ms)
;   H  second now_ms() call within 5000 ms of the first
;      (monotonic + bounded)

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern gettimeofday, sleep_ms, getrusage, time_diff_us, now_ms

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
tv1: resb TIMEVAL_SIZE
tv2: resb TIMEVAL_SIZE
tv3: resb TIMEVAL_SIZE
tv4: resb TIMEVAL_SIZE
ru:  resb 144                        ; struct rusage — 144 bytes on both platforms

section .text

_start:
_main:
    ; ---- 1: gettimeofday(&tv1, NULL) → 0 ----
    mov byte [fail_id], '1'
    lea rdi, [tv1]
    xor esi, esi
    call gettimeofday
    test rax, rax
    jnz .fail

    ; ---- 2: tv1.tv_sec >= 1_700_000_000 ----
    mov byte [fail_id], '2'
    mov rax, [tv1 + TV_SEC_OFF]
    mov rbx, 1700000000
    cmp rax, rbx
    jl .fail

    ; ---- 3: tv1.tv_usec < 1_000_000 ----
    mov byte [fail_id], '3'
    mov eax, [tv1 + TV_USEC_OFF]
    cmp eax, 1000000
    jae .fail

    ; ---- 4: gettimeofday(&tv2, NULL) → 0 ----
    mov byte [fail_id], '4'
    lea rdi, [tv2]
    xor esi, esi
    call gettimeofday
    test rax, rax
    jnz .fail

    ; ---- 5: tv2 >= tv1 ----
    mov byte [fail_id], '5'
    mov rax, [tv2 + TV_SEC_OFF]
    mov rbx, [tv1 + TV_SEC_OFF]
    cmp rax, rbx
    jg .sec_ok               ; tv2.sec > tv1.sec — done
    jl .fail                 ; tv2.sec < tv1.sec — went backward
    mov eax, [tv2 + TV_USEC_OFF]
    mov ebx, [tv1 + TV_USEC_OFF]
    cmp eax, ebx
    jl .fail                 ; same sec, tv2.usec < tv1.usec
.sec_ok:

    ; ---- 6: (tv2 - tv1) sec bounded ----
    mov byte [fail_id], '6'
    mov rax, [tv2 + TV_SEC_OFF]
    sub rax, [tv1 + TV_SEC_OFF]
    cmp rax, 10
    jg .fail

    ; ---- 7: gettimeofday(&tv3, NULL) → 0 ----
    mov byte [fail_id], '7'
    lea rdi, [tv3]
    xor esi, esi
    call gettimeofday
    test rax, rax
    jnz .fail

    ; ---- 8: sleep_ms(50) → 0 ----
    mov byte [fail_id], '8'
    mov edi, 50
    call sleep_ms
    test rax, rax
    jnz .fail

    ; ---- 9: gettimeofday(&tv4, NULL) → 0 ----
    mov byte [fail_id], '9'
    lea rdi, [tv4]
    xor esi, esi
    call gettimeofday
    test rax, rax
    jnz .fail

    ; ---- A/B: (tv4 - tv3) in microseconds within [40_000, 2_000_000] ----
    ; Compute delta_us = (tv4.sec - tv3.sec) * 1_000_000
    ;                  + (tv4.usec - tv3.usec)
    ; using signed 64-bit arithmetic — the subtraction can go
    ; slightly negative on the usec side if tv3.usec > tv4.usec,
    ; which is fine because the sec delta absorbs the borrow.
    mov byte [fail_id], 'A'
    mov rax, [tv4 + TV_SEC_OFF]
    sub rax, [tv3 + TV_SEC_OFF]
    mov rcx, 1000000
    imul rax, rcx
    mov edx, [tv4 + TV_USEC_OFF]
    sub edx, [tv3 + TV_USEC_OFF]
    movsxd rdx, edx                  ; sign-extend the usec delta
    add rax, rdx                     ; rax = elapsed microseconds
    cmp rax, 40000
    jl .fail

    mov byte [fail_id], 'B'
    cmp rax, 2000000
    jge .fail

    ; ---- C: getrusage(RUSAGE_SELF, &ru) → 0 ----
    mov byte [fail_id], 'C'
    xor edi, edi                     ; RUSAGE_SELF = 0
    lea rsi, [ru]
    call getrusage
    test rax, rax
    jnz .fail

    ; ---- D: ru.ru_utime tv_sec >= 0 && tv_usec >= 0 ----
    mov byte [fail_id], 'D'
    mov rax, [ru + RU_UTIME_OFF + TV_SEC_OFF]
    test rax, rax
    js .fail
    mov eax, [ru + RU_UTIME_OFF + TV_USEC_OFF]
    test eax, eax
    js .fail

    ; ---- E: time_diff_us(&tv4, &tv3) >= 40_000 ----
    ; Same 50ms measurement as sub-check A, this time expressed
    ; via the util helper — proves it computed a plausible
    ; positive delta.
    mov byte [fail_id], 'E'
    lea rdi, [tv4]
    lea rsi, [tv3]
    call time_diff_us
    cmp rax, 40000
    jl .fail

    ; ---- F: time_diff_us(&tv3, &tv4) < 0 ----
    ; Reversed args produce a negative delta — a useful
    ; sentinel for callers that want to detect an obvious
    ; argument-order mistake.
    mov byte [fail_id], 'F'
    lea rdi, [tv3]
    lea rsi, [tv4]
    call time_diff_us
    test rax, rax
    jns .fail

    ; ---- v1.3: now_ms plausibility -----------------------------
    ; G: now_ms() >= 1_700_000_000_000  (November 2023 in ms)
    ;    proves the helper composed gettimeofday + ms math
    ;    correctly (not just returning 0 or a random value)
    mov byte [fail_id], 'G'
    call now_ms
    mov rcx, 1700000000000
    cmp rax, rcx
    jl .fail
    mov r14, rax                     ; save the first ms reading

    ; H: a second now_ms() call within a few ms of the first
    ;    proves the wrapper is monotonic within one process
    ;    and doesn't jitter wildly (upper bound 5_000 ms so a
    ;    loaded CI runner still fits comfortably)
    mov byte [fail_id], 'H'
    call now_ms
    sub rax, r14                     ; delta ms since sub-check G
    cmp rax, 0
    jl .fail                         ; must not go backward
    cmp rax, 5000
    jg .fail                         ; must be bounded

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall
