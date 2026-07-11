; resolv-smoke.asm — end-to-end smoke test for libresolv's
; resolv_a() against the Python mock DNS server in mock-dns.py.
;
; The harness (run.sh) spawns the mock server, waits for it to
; publish its port to a file, assembles this test with
; -DDNS_PORT=<n>, and links it against libresolv + libsock +
; libasm. On success this program prints "PASS\n" and exits 0.
; On the first failing check it prints "FAIL:<id>\n" and exits
; 1. Sub-check ids:
;
;   1 resolv_a("libresolv-ok.test", 127.0.0.1:port, &ip) == 0
;   2 the returned ip == 203.0.113.42 (RFC 5737 TEST-NET-3)
;   3 resolv_a("libresolv-nxdomain.test", …) == -ENOENT
;   4 resolv_a("libresolv-servfail.test", …) == -EIO
;   5 resolv_a("", …) rejected with -EINVAL at the encode step
;
; The mock listens on a kernel-assigned ephemeral port; that
; port arrives here as the assemble-time define DNS_PORT. Every
; wrapper is invoked via the ordinary System V ABI — the same
; code path a real consumer would use.

%ifndef DNS_PORT
%define DNS_PORT 5353                ; local default so this
                                     ; file assembles standalone
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
name_ok:       db "libresolv-ok.test", 0
name_nx:       db "libresolv-nxdomain.test", 0
name_sf:       db "libresolv-servfail.test", 0
name_empty:    db 0                  ; empty string (single NUL)
expected_ip:   db 203, 0, 113, 42    ; wire-order bytes for OK_NAME

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
    ; ---- 1: resolv_a("libresolv-ok.test", 127.0.0.1:port, &ip) == 0 ----
    mov byte [fail_id], '1'
    lea rdi, [name_ok]
    mov esi, 0x0100007F              ; 127.0.0.1 (u32, network order)
    mov edx, DNS_PORT                ; port in host order — resolv_a swaps
    lea rcx, [ip_buf]
    call resolv_a
    test rax, rax
    jnz .fail

    ; ---- 2: ip_buf matches 203.0.113.42 ----
    mov byte [fail_id], '2'
    mov eax, [rel expected_ip]
    cmp eax, dword [ip_buf]
    jne .fail

    ; ---- 3: NXDOMAIN → -ENOENT (-2) ----
    mov byte [fail_id], '3'
    lea rdi, [name_nx]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip_buf]
    call resolv_a
    cmp rax, -2
    jne .fail

    ; ---- 4: SERVFAIL → -EIO (-5) ----
    mov byte [fail_id], '4'
    lea rdi, [name_sf]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip_buf]
    call resolv_a
    cmp rax, -5
    jne .fail

    ; ---- 5: empty name → -EINVAL (-22), no packet ever sent ----
    mov byte [fail_id], '5'
    lea rdi, [name_empty]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip_buf]
    call resolv_a
    cmp rax, -22
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
