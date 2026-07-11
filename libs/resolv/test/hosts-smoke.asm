; hosts-smoke.asm — smoke test for resolv_hosts_lookup.
;
; Reads a /etc/hosts-format file the harness populated at
; HOSTS_PATH (injected via -DHOSTS_PATH="/tmp/…") and exercises
; every documented path through the parser:
;
;   1 canonical match: "example.test" → 203.0.113.42
;   2 alias match: "example" (bare alias) → 203.0.113.42
;   3 case-insensitive match: "EXAMPLE.test" → 203.0.113.42
;   4 second-entry match: "backup.test" → 198.51.100.7
;   5 miss: "not-in-file.test" → -ENOENT
;   6 comment respected: "comment.test" (in a "# …" line) → miss
;   7 non-IPv4 line skipped: "ipv6-only.test" → miss
;   8 non-existent file → -ENOENT (from open)
;
; The fixture file created by run.sh has this content:
;
;   # test hosts file for libresolv v1.1
;   203.0.113.42 example.test example
;   fe80::1 ipv6-only.test
;   198.51.100.7 backup.test
;   # 192.0.2.1 comment.test

%ifndef HOSTS_PATH
%define HOSTS_PATH "/tmp/libresolv-hosts-default"
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern resolv_hosts_lookup

global _start
global _main

section .rodata
hosts_path:  db HOSTS_PATH, 0
missing_path: db "/proc/libresolv/does-not-exist-", 0

n_ok:        db "example.test", 0
n_alias:     db "example", 0
n_upper:     db "EXAMPLE.test", 0
n_backup:    db "backup.test", 0
n_none:      db "not-in-file.test", 0
n_comment:   db "comment.test", 0
n_ipv6:      db "ipv6-only.test", 0

exp_ok:      db 203, 0, 113, 42
exp_backup:  db 198, 51, 100, 7

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
    ; 1: canonical hostname match
    mov byte [fail_id], '1'
    lea rdi, [hosts_path]
    lea rsi, [n_ok]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ok]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 2: alias match
    mov byte [fail_id], '2'
    lea rdi, [hosts_path]
    lea rsi, [n_alias]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ok]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 3: case-insensitive match
    mov byte [fail_id], '3'
    lea rdi, [hosts_path]
    lea rsi, [n_upper]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ok]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 4: match against a later entry
    mov byte [fail_id], '4'
    lea rdi, [hosts_path]
    lea rsi, [n_backup]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    test rax, rax
    jnz .fail
    mov eax, [rel exp_backup]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 5: name not present → -ENOENT
    mov byte [fail_id], '5'
    lea rdi, [hosts_path]
    lea rsi, [n_none]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    cmp rax, -2
    jne .fail

    ; 6: name is commented out → -ENOENT
    mov byte [fail_id], '6'
    lea rdi, [hosts_path]
    lea rsi, [n_comment]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    cmp rax, -2
    jne .fail

    ; 7: line has an IPv6 (non-IPv4) address; skipped → -ENOENT
    mov byte [fail_id], '7'
    lea rdi, [hosts_path]
    lea rsi, [n_ipv6]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    cmp rax, -2
    jne .fail

    ; 8: file does not exist → negative errno from open()
    mov byte [fail_id], '8'
    lea rdi, [missing_path]
    lea rsi, [n_ok]
    lea rdx, [ip_buf]
    call resolv_hosts_lookup
    test rax, rax
    jns .fail

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
