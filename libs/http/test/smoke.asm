; smoke.asm — cover http_parse_request_line end to end.
;
; Standalone. Prints "PASS\n" to stdout and exits 0 when every
; sub-check passes; prints "FAIL:<id>\n" to stderr via libasm's
; `panic` and exits 1 otherwise.
;
; Sub-check ids:
;
;   1  "GET / HTTP/1.1\r\n"      → 16 bytes, method="GET",
;                                  target="/", version=11
;   2  "POST /submit HTTP/1.0\r\n" → 22 bytes, method="POST",
;                                  target="/submit", version=10
;   3  "DELETE /items/42 HTTP/1.1\r\n" → 26 bytes
;   4  "GET" (no SP)             → -HTTP_EAGAIN
;   5  "GET / HTTP/1.1\r"        → -HTTP_EAGAIN (CRLF half)
;   6  " / HTTP/1.1\r\n"         → -HTTP_EINVAL (zero-length method)
;   7  "GET  HTTP/1.1\r\n"       → -HTTP_EINVAL (zero-length target)
;   8  "GET / HTTP/2.0\r\n"      → -HTTP_EINVAL (wrong major/prefix)
;   9  "GET / HTTP/1.9\r\n"      → -HTTP_EINVAL (unsupported minor)
;   A  "GET / HTTP/1.1\n\r"      → -HTTP_EINVAL (LF before CR)

%include "http.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern http_parse_request_line
extern memcmp
extern panic

global _start
global _main

section .rodata
; --- happy-path fixtures ---
line_get:   db "GET / HTTP/1.1", 13, 10
line_get_len equ $ - line_get

line_post:  db "POST /submit HTTP/1.0", 13, 10
line_post_len equ $ - line_post

line_del:   db "DELETE /items/42 HTTP/1.1", 13, 10
line_del_len equ $ - line_del

; --- partial-input fixtures ---
line_short: db "GET"
line_short_len equ $ - line_short

line_no_lf: db "GET / HTTP/1.1", 13
line_no_lf_len equ $ - line_no_lf

; --- malformed fixtures ---
line_lead_sp:  db " / HTTP/1.1", 13, 10
line_lead_sp_len equ $ - line_lead_sp

line_two_sp:   db "GET  HTTP/1.1", 13, 10
line_two_sp_len equ $ - line_two_sp

line_h2:       db "GET / HTTP/2.0", 13, 10
line_h2_len equ $ - line_h2

line_h19:      db "GET / HTTP/1.9", 13, 10
line_h19_len equ $ - line_h19

line_bad_eol:  db "GET / HTTP/1.1", 10, 13
line_bad_eol_len equ $ - line_bad_eol

; --- expected token bytes for happy-path comparison ---
tok_get:  db "GET"
tok_get_len  equ $ - tok_get
tok_slash: db "/"
tok_slash_len equ $ - tok_slash
tok_post: db "POST"
tok_post_len equ $ - tok_post
tok_submit: db "/submit"
tok_submit_len equ $ - tok_submit
tok_delete: db "DELETE"
tok_delete_len equ $ - tok_delete
tok_items42: db "/items/42"
tok_items42_len equ $ - tok_items42

pass_msg:   db "PASS", 10
pass_len    equ $ - pass_msg

section .data
fail_msg:   db "FAIL:?", 10
fail_id     equ fail_msg + 5
fail_len    equ $ - fail_msg

section .bss
rl:         resb REQUEST_LINE_SIZE

section .text

_start:
_main:
    ; ---- 1: GET / HTTP/1.1\r\n ----
    mov  byte [fail_id], '1'
    lea  rdi, [line_get]
    mov  rsi, line_get_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, line_get_len
    jne  .fail
    cmp  qword [rl + RL_METHOD_LEN_OFF], tok_get_len
    jne  .fail
    ; method bytes match "GET"
    mov  rdi, [rl + RL_METHOD_PTR_OFF]
    lea  rsi, [tok_get]
    mov  rdx, tok_get_len
    call memcmp
    test rax, rax
    jnz  .fail
    ; target = "/"
    cmp  qword [rl + RL_TARGET_LEN_OFF], tok_slash_len
    jne  .fail
    mov  rdi, [rl + RL_TARGET_PTR_OFF]
    lea  rsi, [tok_slash]
    mov  rdx, tok_slash_len
    call memcmp
    test rax, rax
    jnz  .fail
    ; version = 11
    cmp  dword [rl + RL_VERSION_OFF], HTTP_VERSION_11
    jne  .fail

    ; ---- 2: POST /submit HTTP/1.0\r\n ----
    mov  byte [fail_id], '2'
    lea  rdi, [line_post]
    mov  rsi, line_post_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, line_post_len
    jne  .fail
    cmp  qword [rl + RL_METHOD_LEN_OFF], tok_post_len
    jne  .fail
    mov  rdi, [rl + RL_METHOD_PTR_OFF]
    lea  rsi, [tok_post]
    mov  rdx, tok_post_len
    call memcmp
    test rax, rax
    jnz  .fail
    cmp  qword [rl + RL_TARGET_LEN_OFF], tok_submit_len
    jne  .fail
    mov  rdi, [rl + RL_TARGET_PTR_OFF]
    lea  rsi, [tok_submit]
    mov  rdx, tok_submit_len
    call memcmp
    test rax, rax
    jnz  .fail
    cmp  dword [rl + RL_VERSION_OFF], HTTP_VERSION_10
    jne  .fail

    ; ---- 3: DELETE /items/42 HTTP/1.1\r\n ----
    mov  byte [fail_id], '3'
    lea  rdi, [line_del]
    mov  rsi, line_del_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, line_del_len
    jne  .fail
    cmp  qword [rl + RL_METHOD_LEN_OFF], tok_delete_len
    jne  .fail
    mov  rdi, [rl + RL_METHOD_PTR_OFF]
    lea  rsi, [tok_delete]
    mov  rdx, tok_delete_len
    call memcmp
    test rax, rax
    jnz  .fail
    cmp  qword [rl + RL_TARGET_LEN_OFF], tok_items42_len
    jne  .fail
    mov  rdi, [rl + RL_TARGET_PTR_OFF]
    lea  rsi, [tok_items42]
    mov  rdx, tok_items42_len
    call memcmp
    test rax, rax
    jnz  .fail
    cmp  dword [rl + RL_VERSION_OFF], HTTP_VERSION_11
    jne  .fail

    ; ---- 4: "GET" alone → -EAGAIN ----
    mov  byte [fail_id], '4'
    lea  rdi, [line_short]
    mov  rsi, line_short_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EAGAIN
    jne  .fail

    ; ---- 5: "GET / HTTP/1.1\r" (missing LF) → -EAGAIN ----
    mov  byte [fail_id], '5'
    lea  rdi, [line_no_lf]
    mov  rsi, line_no_lf_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EAGAIN
    jne  .fail

    ; ---- 6: leading SP → zero-length method → -EINVAL ----
    mov  byte [fail_id], '6'
    lea  rdi, [line_lead_sp]
    mov  rsi, line_lead_sp_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EINVAL
    jne  .fail

    ; ---- 7: two SPs in a row → zero-length target → -EINVAL ----
    mov  byte [fail_id], '7'
    lea  rdi, [line_two_sp]
    mov  rsi, line_two_sp_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EINVAL
    jne  .fail

    ; ---- 8: HTTP/2.0 (wrong major) → -EINVAL ----
    mov  byte [fail_id], '8'
    lea  rdi, [line_h2]
    mov  rsi, line_h2_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EINVAL
    jne  .fail

    ; ---- 9: HTTP/1.9 (unsupported minor) → -EINVAL ----
    mov  byte [fail_id], '9'
    lea  rdi, [line_h19]
    mov  rsi, line_h19_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EINVAL
    jne  .fail

    ; ---- A: LF before CR → -EINVAL ----
    mov  byte [fail_id], 'A'
    lea  rdi, [line_bad_eol]
    mov  rsi, line_bad_eol_len
    lea  rdx, [rl]
    call http_parse_request_line
    cmp  rax, -HTTP_EINVAL
    jne  .fail

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
    lea  rdi, [fail_msg]
    mov  esi, fail_len
    call panic
    ; unreachable
