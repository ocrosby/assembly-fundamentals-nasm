; resolvconf-smoke.asm — smoke test for resolv_conf_read.
;
; Reads a resolv.conf-format file the harness populated at
; CONF_PATH (injected via -DCONF_PATH="/tmp/…") and asserts:
;
;   1 first parseable nameserver wins (192.0.2.53), not the
;     commented-out earlier one (198.51.100.53) nor the later
;     one (203.0.113.53)
;   2 non-existent file → negative errno from open()
;   3 file with no nameserver line → -ENOENT
;
; The primary fixture file created by run.sh has this content:
;
;   # test resolv.conf for libresolv v1.1
;   # nameserver 198.51.100.53   (commented, should be skipped)
;   domain test
;   nameserver 192.0.2.53
;   nameserver 203.0.113.53      (later — should be ignored)
;
; A second fixture (CONF_EMPTY_PATH) has no nameserver directive
; at all so we can exercise the empty case.

%ifndef CONF_PATH
%define CONF_PATH "/tmp/libresolv-resolvconf-default"
%endif
%ifndef CONF_EMPTY_PATH
%define CONF_EMPTY_PATH "/tmp/libresolv-resolvconf-empty-default"
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern resolv_conf_read

global _start
global _main

section .rodata
conf_path:       db CONF_PATH, 0
conf_empty_path: db CONF_EMPTY_PATH, 0
missing_path:    db "/proc/libresolv/does-not-exist-", 0

; Expected: 192.0.2.53 as network-order bytes.
exp_ip:          db 192, 0, 2, 53

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
ip_buf:   resb 4

section .text

_start:
_main:
    ; 1: first parseable nameserver wins
    mov byte [fail_id], '1'
    lea rdi, [conf_path]
    lea rsi, [ip_buf]
    call resolv_conf_read
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ip]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 2: non-existent file
    mov byte [fail_id], '2'
    lea rdi, [missing_path]
    lea rsi, [ip_buf]
    call resolv_conf_read
    test rax, rax
    jns .fail

    ; 3: file exists but has no nameserver directive
    mov byte [fail_id], '3'
    lea rdi, [conf_empty_path]
    lea rsi, [ip_buf]
    call resolv_conf_read
    cmp rax, -2
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
