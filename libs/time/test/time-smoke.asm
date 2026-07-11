; time-smoke.asm — v1.0 gettimeofday coverage.
;
; Standalone. Calls libtime's gettimeofday twice back-to-back and
; verifies the returned struct timeval is plausible and
; monotonic within one process.
;
; Sub-check ids:
;
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

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern gettimeofday

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
