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
;
; v1.4 — monotonic_ms util helper (deliberately asymmetric):
;   I  Linux: monotonic_ms() >= 0.
;      macOS: monotonic_ms() == -78 (-ENOSYS).
;   J  Linux only: second call within 5000 ms of the first,
;      non-decreasing (monotonic invariant).

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern gettimeofday, sleep_ms, getrusage, time_diff_us, now_ms, monotonic_ms
extern format_time_rfc1123          ; libtime v1.5
extern memcmp                       ; libstr — smoke uses it for byte-exact date compare
extern panic                        ; libasm v1.1

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

; v1.5 fixtures — RFC 1123 date-string references.
; Each is exactly 29 bytes, matching the fixed-form output.
date_epoch:  db "Thu, 01 Jan 1970 00:00:00 GMT"
date_rfc:    db "Sun, 06 Nov 1994 08:49:37 GMT"  ; RFC 7231 §7.1.1.1
date_y2k:    db "Sat, 01 Jan 2000 00:00:00 GMT"
date_fri:    db "Fri, 13 Feb 2009 23:31:30 GMT"  ; the 1234567890 timestamp

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
buf_date: resb 32                    ; RFC 1123 output — 29 bytes + slack

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

    ; ---- v1.4: monotonic_ms — deliberately asymmetric ----
    ; I: Linux → non-negative monotonic ms.
    ;    macOS → -78 (-ENOSYS). Callers detect and fall back.
    mov byte [fail_id], 'I'
    call monotonic_ms
%ifdef MACOS
    cmp rax, -78
    jne .fail
%else
    test rax, rax
    js .fail
    mov r15, rax                     ; save first monotonic reading

    ; J: on Linux, a second call must be >= the first and
    ;    within a small bound (guards against wildly wrong
    ;    unit conversion — e.g. seconds treated as ms would
    ;    produce a 1000× drift).
    mov byte [fail_id], 'J'
    call monotonic_ms
    sub rax, r15
    cmp rax, 0
    jl .fail                         ; monotonic can never go backward
    cmp rax, 5000
    jg .fail                         ; delta bounded (5s slack)
%endif

    ; ---- v1.5: format_time_rfc1123 ------------------------
    ; K: seconds = 0 → "Thu, 01 Jan 1970 00:00:00 GMT"
    ;    Epoch check — proves the algorithm base case,
    ;    the weekday offset (Thursday = 4), and every
    ;    zero-padded field.
    mov byte [fail_id], 'K'
    xor edi, edi
    lea rsi, [buf_date]
    call format_time_rfc1123
    lea rdi, [buf_date]
    lea rsi, [date_epoch]
    mov edx, 29
    call memcmp
    test rax, rax
    jnz .fail

    ; L: seconds = 784111777 → "Sun, 06 Nov 1994 08:49:37 GMT"
    ;    The RFC 7231 §7.1.1.1 canonical example. Non-trivial
    ;    year, non-Jan month, non-first day, non-zero HMS.
    mov byte [fail_id], 'L'
    mov rdi, 784111777
    lea rsi, [buf_date]
    call format_time_rfc1123
    lea rdi, [buf_date]
    lea rsi, [date_rfc]
    mov edx, 29
    call memcmp
    test rax, rax
    jnz .fail

    ; M: seconds = 946684800 → "Sat, 01 Jan 2000 00:00:00 GMT"
    ;    Y2K boundary — proves the century tick over from
    ;    1999 to 2000 and that the leap-year branch in
    ;    Hinnant's algorithm does the right thing.
    mov byte [fail_id], 'M'
    mov rdi, 946684800
    lea rsi, [buf_date]
    call format_time_rfc1123
    lea rdi, [buf_date]
    lea rsi, [date_y2k]
    mov edx, 29
    call memcmp
    test rax, rax
    jnz .fail

    ; N: seconds = 1234567890 → "Fri, 13 Feb 2009 23:31:30 GMT"
    ;    A memorable middle-of-the-range timestamp; catches
    ;    off-by-one bugs in weekday, day-of-month, and the
    ;    HH:MM:SS three-way split.
    mov byte [fail_id], 'N'
    mov rdi, 1234567890
    lea rsi, [buf_date]
    call format_time_rfc1123
    lea rdi, [buf_date]
    lea rsi, [date_fri]
    mov edx, 29
    call memcmp
    test rax, rax
    jnz .fail

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
    ; libasm v1.1's panic writes to stderr and exits(1). The
    ; fail_id byte was patched by whichever sub-check failed,
    ; so fail_msg still starts with "FAIL:<id>".
    lea rdi, [fail_msg]
    mov esi, fail_len
    call panic
    ; unreachable
