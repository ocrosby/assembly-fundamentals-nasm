; inet4-smoke.asm — smoke test for libsock's byte-order helpers
; and its strict IPv4 text conversion (inet_pton4 / inet_ntop4).
;
; Prints "PASS\n" and exits 0 when every sub-check passes.
; Prints "FAIL:<id>\n" to stderr and exits 1 on the first failure,
; where <id> is a single character identifying the failing check:
;
;   1..4 — htons / htonl / ntohs / ntohl byte-swap round-trips
;   5..9 — inet_pton4 success + four rejection cases (out-of-range
;          octet, leading zero, trailing garbage, missing octet)
;   A..C — inet_ntop4 round-trip, buffer-too-small NULL return,
;          all-zero address
;   D..E — inet_pton4 remaining branches: leading non-digit char
;          (first-char-not-digit path in .next_octet), all-zero
;          address success (single-digit "0" path via .store)
;
; Together these hit every conditional in inet-pton4.asm and
; every branch of inet-ntop4.asm's EMIT_BYTE macro.
;
; No syscalls into libsock other than the routines under test —
; the write() and exit() calls are made directly against the
; kernel so the harness stays purely a client of the library.

extern htons, ntohs, htonl, ntohl, inet_pton4, inet_ntop4
extern strcmp                       ; libstr v1.0

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

global _start
global _main

section .data
addr_ok:    db "192.168.1.42", 0
addr_bad:   db "1.2.3.256", 0
addr_lz:    db "01.2.3.4", 0
addr_extra: db "1.2.3.4.5", 0
addr_short: db "1.2.3", 0
addr_alpha: db "a.1.2.3", 0          ; leading non-digit — must fail
addr_zero:  db "0.0.0.0", 0          ; every octet is single '0' — must succeed
pass_msg:   db "PASS", 10
pass_len:   equ $ - pass_msg
fail_msg:   db "FAIL:", 32
fail_id:    db "  ", 10
fail_len:   equ $ - fail_msg

section .bss
buf:        resq 1
outstr:     resb 32

section .text

_start:
_main:
    ; T1: htons(0x1234) == 0x3412
    mov edi, 0x1234
    call htons
    mov r15b, '1'
    cmp rax, 0x3412
    jne .fail

    ; T2: htonl(0x12345678) == 0x78563412
    mov edi, 0x12345678
    call htonl
    mov r15b, '2'
    cmp rax, 0x78563412
    jne .fail

    ; T3: ntohs(0x3412) == 0x1234
    mov edi, 0x3412
    call ntohs
    mov r15b, '3'
    cmp rax, 0x1234
    jne .fail

    ; T4: ntohl(0x78563412) == 0x12345678
    mov edi, 0x78563412
    call ntohl
    mov r15b, '4'
    cmp rax, 0x12345678
    jne .fail

    ; T5: inet_pton4("192.168.1.42", &buf) == 1 and buf == 0x2A01A8C0
    lea rdi, [addr_ok]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, '5'
    cmp rax, 1
    jne .fail
    mov eax, dword [buf]
    cmp eax, 0x2A01A8C0
    jne .fail

    ; T6: inet_pton4("1.2.3.256") == 0
    lea rdi, [addr_bad]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, '6'
    test rax, rax
    jnz .fail

    ; T7: inet_pton4("01.2.3.4") == 0 (leading zero rejected)
    lea rdi, [addr_lz]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, '7'
    test rax, rax
    jnz .fail

    ; T8: inet_pton4("1.2.3.4.5") == 0 (trailing garbage)
    lea rdi, [addr_extra]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, '8'
    test rax, rax
    jnz .fail

    ; T9: inet_pton4("1.2.3") == 0 (missing octet)
    lea rdi, [addr_short]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, '9'
    test rax, rax
    jnz .fail

    ; T10: inet_ntop4(0x2A01A8C0, out, 32) round-trips to "192.168.1.42"
    mov edi, 0x2A01A8C0
    lea rsi, [outstr]
    mov rdx, 32
    call inet_ntop4
    mov r15b, 'A'
    test rax, rax
    jz .fail
    lea rdi, [outstr]
    lea rsi, [addr_ok]
    call strcmp
    test rax, rax
    jnz .fail                       ; strcmp returns 0 on match

    ; T11: inet_ntop4(x, out, 15) == NULL (too small)
    xor edi, edi
    lea rsi, [outstr]
    mov rdx, 15
    call inet_ntop4
    mov r15b, 'B'
    test rax, rax
    jnz .fail

    ; T12: inet_ntop4(0, out, 16) == "0.0.0.0"
    xor edi, edi
    lea rsi, [outstr]
    mov rdx, 16
    call inet_ntop4
    mov r15b, 'C'
    test rax, rax
    jz .fail
    mov al, [outstr + 0]
    cmp al, '0'
    jne .fail
    mov al, [outstr + 1]
    cmp al, '.'
    jne .fail
    mov al, [outstr + 7]
    test al, al
    jnz .fail

    ; T13: inet_pton4("a.1.2.3") == 0 — first character is not a
    ; decimal digit. Hits the very first `ja .fail` in .next_octet
    ; that had never been exercised before this sub-check.
    lea rdi, [addr_alpha]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, 'D'
    test rax, rax
    jnz .fail

    ; T14: inet_pton4("0.0.0.0") — every octet is a single '0'.
    ; Exercises the "leading '0' as the whole octet" fall-through
    ; to .store (line 55 in inet-pton4.asm) that the strictness
    ; tests never reach.
    lea rdi, [addr_zero]
    lea rsi, [buf]
    call inet_pton4
    mov r15b, 'E'
    cmp rax, 1
    jne .fail
    mov eax, dword [buf]
    test eax, eax
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
    mov [fail_id], r15b
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall

