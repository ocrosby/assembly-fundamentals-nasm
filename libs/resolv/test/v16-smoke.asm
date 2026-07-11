; v16-smoke.asm — end-to-end exercise for the v1.6 TC=1 → TCP
; retry path against the mock DNS server.
;
; Sub-checks (against DNS_PORT injected by run.sh):
;
;   1  resolv_a("libresolv-truncated.test", 127.0.0.1:DNS_PORT, &ip)
;      → 0; ip == 203.0.113.42. The mock's UDP handler for this
;      name sends a header-only response with TC=1 set. libresolv
;      must notice the truncation bit, open a TCP connection to
;      the same resolver, replay the query with a 2-byte
;      big-endian length prefix, and read the untruncated
;      answer back. The mock's TCP handler responds with the
;      real A record; the assertion is that the whole loop
;      completes and populates ip correctly.
;   2  resolv_a("libresolv-ok.test", …, &ip) → 0; ip == same.
;      A control case that goes over UDP only — the mock does
;      not set TC=1 for this name, so the TCP path is skipped.
;      Kept in the same test binary so a regression in the
;      non-truncation path is visible here too.

%ifndef DNS_PORT
%define DNS_PORT 5353
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern resolv_a

global _start
global _main

section .rodata
n_trunc: db "libresolv-truncated.test", 0
n_ok:    db "libresolv-ok.test", 0

; Expected: 203.0.113.42 as four network-order bytes.
exp_ip:  db 203, 0, 113, 42

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
ip_buf:  resb 4

section .text

_start:
_main:
    ; 1: TC=1 → TCP retry populates the real A record.
    mov byte [fail_id], '1'
    lea rdi, [n_trunc]
    mov esi, 0x0100007F              ; 127.0.0.1 net-order u32
    mov edx, DNS_PORT
    lea rcx, [ip_buf]
    call resolv_a
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ip]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 2: control — UDP-only path still resolves.
    mov byte [fail_id], '2'
    lea rdi, [n_ok]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip_buf]
    call resolv_a
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ip]
    cmp eax, dword [ip_buf]
    jne .fail

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
