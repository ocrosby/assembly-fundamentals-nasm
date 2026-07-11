; resolvconf-smoke.asm — smoke test for resolv_conf_read and
; (v1.4) resolv_conf_read_all.
;
; Reads a resolv.conf-format file the harness populated at
; CONF_PATH (injected via -DCONF_PATH="/tmp/…") and asserts:
;
;   1 first parseable nameserver wins (192.0.2.53), not the
;     commented-out earlier one nor the later one
;   2 non-existent file → negative errno from open()
;   3 file with no nameserver line → -ENOENT
;   4 resolv_conf_read_all returns count=2 with entries
;     [192.0.2.53:53, 203.0.113.53:53] in listed order
;   5 resolv_conf_read_all on the empty fixture returns 0
;     (not -ENOENT — the count-return convention treats
;     "empty" as the natural fold)
;   6 max_count clamps: asking for 1 entry yields 1
;   7 port shorthand + malformed-port skipping — the ports
;     fixture (see below) mixes valid :port suffixes with
;     three invalid ones (port 0, port > u16, non-digit). The
;     parser must produce exactly the two valid entries.
;
; The primary fixture file created by run.sh has this content:
;
;   # test resolv.conf for libresolv v1.1
;   # nameserver 198.51.100.53   (commented, should be skipped)
;   domain test
;   nameserver 192.0.2.53
;   nameserver 203.0.113.53
;
; The port-focused fixture (CONF_PORTS_PATH) exercises the
; :port suffix parser and the "silently skip malformed" rule:
;
;   nameserver 127.0.0.1:5353
;   nameserver 10.0.0.1:0        (port 0 rejected)
;   nameserver 10.0.0.2:70000    (out of u16 range)
;   nameserver 10.0.0.3:abc      (non-digit)
;   nameserver 198.51.100.1:9999
;
; Sub-check IDs past 9 use letters — see hosts-smoke for the
; convention. This file stays within 1..9.

%ifndef CONF_PATH
%define CONF_PATH "/tmp/libresolv-resolvconf-default"
%endif
%ifndef CONF_EMPTY_PATH
%define CONF_EMPTY_PATH "/tmp/libresolv-resolvconf-empty-default"
%endif
%ifndef CONF_PORTS_PATH
%define CONF_PORTS_PATH "/tmp/libresolv-resolvconf-ports-default"
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern resolv_conf_read, resolv_conf_read_all

global _start
global _main

section .rodata
conf_path:       db CONF_PATH, 0
conf_empty_path: db CONF_EMPTY_PATH, 0
conf_ports_path: db CONF_PORTS_PATH, 0
missing_path:    db "/proc/libresolv/does-not-exist-", 0

; Expected: 192.0.2.53 as network-order bytes.
exp_ip:          db 192, 0, 2, 53
; Second entry from CONF_PATH: 203.0.113.53
exp_ip2:         db 203, 0, 113, 53
; From CONF_PORTS_PATH: 127.0.0.1 and 198.51.100.1
exp_ports_ip1:   db 127, 0, 0, 1
exp_ports_ip2:   db 198, 51, 100, 1

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
ip_buf:      resb 4
; resolv_conf_read_all writes 8-byte packed entries. Reserve
; room for MAX_RESOLVERS (8) so we can accept any legal count.
entry_buf:   resb 64

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

    ; 4: resolv_conf_read_all(conf, buf, 8) → count=2 with
    ; both entries at default port 53.
    mov byte [fail_id], '4'
    lea rdi, [conf_path]
    lea rsi, [entry_buf]
    mov edx, 8
    call resolv_conf_read_all
    cmp rax, 2
    jne .fail
    ; entry_buf[0].ip == 192.0.2.53
    mov eax, [rel exp_ip]
    cmp eax, dword [entry_buf + 0]
    jne .fail
    ; entry_buf[0].port == 53
    movzx eax, word [entry_buf + 4]
    cmp eax, 53
    jne .fail
    ; entry_buf[1].ip == 203.0.113.53
    mov eax, [rel exp_ip2]
    cmp eax, dword [entry_buf + 8]
    jne .fail
    ; entry_buf[1].port == 53
    movzx eax, word [entry_buf + 12]
    cmp eax, 53
    jne .fail

    ; 5: resolv_conf_read_all on empty fixture → count=0
    ; (NOT -ENOENT — that is _read's convention only)
    mov byte [fail_id], '5'
    lea rdi, [conf_empty_path]
    lea rsi, [entry_buf]
    mov edx, 8
    call resolv_conf_read_all
    test rax, rax
    jnz .fail

    ; 6: max_count=1 clamps to the first entry.
    mov byte [fail_id], '6'
    lea rdi, [conf_path]
    lea rsi, [entry_buf]
    mov edx, 1
    call resolv_conf_read_all
    cmp rax, 1
    jne .fail
    mov eax, [rel exp_ip]
    cmp eax, dword [entry_buf + 0]
    jne .fail

    ; 7: port shorthand — CONF_PORTS_PATH has two valid entries
    ; interleaved with three malformed lines. Expect count=2
    ; with ports 5353 and 9999.
    mov byte [fail_id], '7'
    lea rdi, [conf_ports_path]
    lea rsi, [entry_buf]
    mov edx, 8
    call resolv_conf_read_all
    cmp rax, 2
    jne .fail
    mov eax, [rel exp_ports_ip1]
    cmp eax, dword [entry_buf + 0]
    jne .fail
    movzx eax, word [entry_buf + 4]
    cmp eax, 5353
    jne .fail
    mov eax, [rel exp_ports_ip2]
    cmp eax, dword [entry_buf + 8]
    jne .fail
    movzx eax, word [entry_buf + 12]
    cmp eax, 9999
    jne .fail

    ; (Sub-check 8 folded into 7 — the count-of-2 assertion
    ; there already proves the three malformed :port lines
    ; were silently skipped. Keeping a separate ID would
    ; require re-reading the count into rax; not worth it.)

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
