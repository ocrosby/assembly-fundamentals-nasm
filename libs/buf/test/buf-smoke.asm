; buf-smoke.asm — v1.0 coverage for libbuf's five entry points.
;
; Standalone. Sub-check ids:
;
; v1.0 — buf_init writes a plausible struct:
;   1  buf_init(&b, 100) → 0
;   2  b.data != 0                (mmap returned an address)
;   3  b.len == 0                 (fresh buffer is empty)
;   4  b.cap == 4096              (100 rounded up to one page)
;
; v1.0 — buf_append writes bytes and advances len:
;   5  buf_append(&b, "hello ", 6) → 0
;   6  b.len == 6
;   7  bytes 0..5 == "hello "
;
;   8  buf_append(&b, "world", 5) → 0
;   9  b.len == 11
;   A  bytes 6..10 == "world"
;
; v1.0 — a large append forces buf_reserve to grow:
;   B  buf_append(&b, xxx5000, 5000) → 0
;   C  b.len == 5011
;   D  b.cap == 8192              (cap*2 = 8192 fits 5011)
;   E  bytes 0..10 still "hello world" (grow preserved payload)
;   F  bytes 11..5010 are all 'X'
;
; v1.0 — buf_reset rewinds len without releasing:
;   G  buf_reset(&b), then b.len == 0
;   H  b.cap == 8192              (unchanged)
;   I  b.data != 0                (unchanged)
;
; v1.0 — buf_free releases and zeros the struct:
;   J  buf_free(&b) → 0
;   K  b.data == 0
;   L  b.len == 0
;   M  b.cap == 0
;
; v1.0 — buf_free on an already-freed struct is a no-op success:
;   N  buf_free(&b) → 0            (data==0 short-circuits)

%include "buf.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern buf_init, buf_free, buf_reserve, buf_append, buf_reset
extern panic                        ; libasm v1.1

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

hello:    db "hello "
hello_len equ $ - hello
world:    db "world"
world_len equ $ - world
combined: db "hello world"
combined_len equ $ - combined

; 5000 'X' bytes — the append that forces a grow past the
; initial 4096-byte cap.
xxx5000:  times 5000 db 'X'
xxx_len   equ $ - xxx5000

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
b:        resb BUF_SIZE

section .text

_start:
_main:
    ; ---- 1: buf_init(&b, 100) → 0 ----
    mov  byte [fail_id], '1'
    lea  rdi, [b]
    mov  esi, 100
    call buf_init
    test rax, rax
    jnz  .fail

    ; ---- 2: b.data != 0 ----
    mov  byte [fail_id], '2'
    mov  rax, [b + BUF_DATA_OFF]
    test rax, rax
    jz   .fail

    ; ---- 3: b.len == 0 ----
    mov  byte [fail_id], '3'
    mov  rax, [b + BUF_LEN_OFF]
    test rax, rax
    jnz  .fail

    ; ---- 4: b.cap == 4096 ----
    mov  byte [fail_id], '4'
    mov  rax, [b + BUF_CAP_OFF]
    cmp  rax, 4096
    jne  .fail

    ; ---- 5: buf_append(&b, "hello ", 6) → 0 ----
    mov  byte [fail_id], '5'
    lea  rdi, [b]
    lea  rsi, [hello]
    mov  edx, hello_len
    call buf_append
    test rax, rax
    jnz  .fail

    ; ---- 6: b.len == 6 ----
    mov  byte [fail_id], '6'
    mov  rax, [b + BUF_LEN_OFF]
    cmp  rax, hello_len
    jne  .fail

    ; ---- 7: data[0..5] == "hello " ----
    mov  byte [fail_id], '7'
    mov  rdi, [b + BUF_DATA_OFF]
    lea  rsi, [hello]
    mov  ecx, hello_len
    cld
    repe cmpsb
    jne  .fail

    ; ---- 8: buf_append(&b, "world", 5) → 0 ----
    mov  byte [fail_id], '8'
    lea  rdi, [b]
    lea  rsi, [world]
    mov  edx, world_len
    call buf_append
    test rax, rax
    jnz  .fail

    ; ---- 9: b.len == 11 ----
    mov  byte [fail_id], '9'
    mov  rax, [b + BUF_LEN_OFF]
    cmp  rax, combined_len
    jne  .fail

    ; ---- A: data[6..10] == "world" ----
    mov  byte [fail_id], 'A'
    mov  rdi, [b + BUF_DATA_OFF]
    add  rdi, hello_len
    lea  rsi, [world]
    mov  ecx, world_len
    cld
    repe cmpsb
    jne  .fail

    ; ---- B: buf_append 5000 X's → 0 ----
    mov  byte [fail_id], 'B'
    lea  rdi, [b]
    lea  rsi, [xxx5000]
    mov  edx, xxx_len
    call buf_append
    test rax, rax
    jnz  .fail

    ; ---- C: b.len == 5011 ----
    mov  byte [fail_id], 'C'
    mov  rax, [b + BUF_LEN_OFF]
    cmp  rax, 5011
    jne  .fail

    ; ---- D: b.cap == 8192 (doubling from 4096 covered 5011) ----
    mov  byte [fail_id], 'D'
    mov  rax, [b + BUF_CAP_OFF]
    cmp  rax, 8192
    jne  .fail

    ; ---- E: data[0..10] still "hello world" ----
    mov  byte [fail_id], 'E'
    mov  rdi, [b + BUF_DATA_OFF]
    lea  rsi, [combined]
    mov  ecx, combined_len
    cld
    repe cmpsb
    jne  .fail

    ; ---- F: data[11..5010] all 'X' ----
    mov  byte [fail_id], 'F'
    mov  rdi, [b + BUF_DATA_OFF]
    add  rdi, combined_len
    mov  rcx, xxx_len
.check_x:
    cmp  byte [rdi], 'X'
    jne  .fail
    inc  rdi
    dec  rcx
    jnz  .check_x

    ; ---- G: buf_reset(&b), b.len == 0 ----
    mov  byte [fail_id], 'G'
    lea  rdi, [b]
    call buf_reset
    mov  rax, [b + BUF_LEN_OFF]
    test rax, rax
    jnz  .fail

    ; ---- H: cap unchanged after reset ----
    mov  byte [fail_id], 'H'
    mov  rax, [b + BUF_CAP_OFF]
    cmp  rax, 8192
    jne  .fail

    ; ---- I: data unchanged after reset ----
    mov  byte [fail_id], 'I'
    mov  rax, [b + BUF_DATA_OFF]
    test rax, rax
    jz   .fail

    ; ---- J: buf_free(&b) → 0 ----
    mov  byte [fail_id], 'J'
    lea  rdi, [b]
    call buf_free
    test rax, rax
    jnz  .fail

    ; ---- K/L/M: struct fully zeroed after free ----
    mov  byte [fail_id], 'K'
    mov  rax, [b + BUF_DATA_OFF]
    test rax, rax
    jnz  .fail

    mov  byte [fail_id], 'L'
    mov  rax, [b + BUF_LEN_OFF]
    test rax, rax
    jnz  .fail

    mov  byte [fail_id], 'M'
    mov  rax, [b + BUF_CAP_OFF]
    test rax, rax
    jnz  .fail

    ; ---- N: double-free is a clean 0 ----
    mov  byte [fail_id], 'N'
    lea  rdi, [b]
    call buf_free
    test rax, rax
    jnz  .fail

    ; PASS
    mov  rax, SYS_write
    mov  edi, 1
    lea  rsi, [pass_msg]
    mov  edx, pass_len
    syscall
    mov  rax, SYS_exit
    xor  edi, edi
    syscall

.fail:
    ; libasm v1.1's panic writes fail_msg to stderr and exits(1).
    lea  rdi, [fail_msg]
    mov  esi, fail_len
    call panic
    ; unreachable
