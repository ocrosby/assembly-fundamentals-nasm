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
;   7 non-IPv4 line skipped: "ipv6-only.test" via v4 lookup → miss
;   8 non-existent file → -ENOENT (from open)
;   9 v6 canonical match: resolv_hosts_lookup6("ipv6-only.test") → fe80::1
;  10 v6 lookup of v4-only name: "example.test" via v6 → -ENOENT
;
; The fail ID stamped into "FAIL:?" is a single character —
; sub-checks past 9 use letters ('a' for 10) so the buffer
; length stays fixed at 6 bytes.
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

extern resolv_hosts_lookup, resolv_hosts_lookup6

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

; fe80::1 as 16 network-order bytes.
exp_v6:      db 0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
ip_buf:   resb 4
ip6_buf:  resb 16

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

    ; 9: v6 canonical match: "ipv6-only.test" → fe80::1
    mov byte [fail_id], '9'
    lea rdi, [hosts_path]
    lea rsi, [n_ipv6]
    lea rdx, [ip6_buf]
    call resolv_hosts_lookup6
    test rax, rax
    jnz .fail
    ; Compare 16 bytes against exp_v6.
    lea rdi, [ip6_buf]
    lea rsi, [exp_v6]
    mov ecx, 16
    call memeq
    test rax, rax
    jz .fail

    ; 10: v6 lookup of a v4-only name skips the v4 line and misses.
    mov byte [fail_id], 'a'
    lea rdi, [hosts_path]
    lea rsi, [n_ok]                 ; "example.test" is a v4 line
    lea rdx, [ip6_buf]
    call resolv_hosts_lookup6
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

; memeq(rdi=a, rsi=b, ecx=len) → rax = 1 if equal else 0
memeq:
    xor edx, edx
.mem_loop:
    cmp edx, ecx
    jge .mem_eq
    mov al, [rdi + rdx]
    cmp al, [rsi + rdx]
    jne .mem_ne
    inc edx
    jmp .mem_loop
.mem_eq:
    mov eax, 1
    ret
.mem_ne:
    xor eax, eax
    ret
