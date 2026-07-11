; v12-smoke.asm — end-to-end exercise for the v1.2 additions
; against the Python mock DNS server in mock-dns.py.
;
; Sub-checks (against DNS_PORT injected by run.sh):
;
;   1  resolv_aaaa("libresolv-aaaa.test", 127.0.0.1:DNS_PORT, &ip16)
;      → 0; ip16 == 2001:db8::42
;   2  resolv_a("libresolv-cname.test", …, &ip4) → 0; ip4 ==
;      203.0.113.42. Exercises the CNAME chase (mock returns
;      a CNAME → libresolv-ok.test, which resolves to
;      203.0.113.42).
;   3  resolv_a("libresolv-loop-a.test", …, &ip4) →
;      -ELOOP. Exercises the hop-limit trip (loop-a → loop-b →
;      loop-a → …).
;   4  resolv_a_all("libresolv-multi.test", …, buf, 4) → 3;
;      the three records match 203.0.113.{1,2,3}.
;   5  resolv_a("libresolv-aaaa.test", …, &ip4) → -ENODATA
;      (the mock returns an A-typed empty answer for this
;      name, so no A records and no CNAME chain).

%ifndef DNS_PORT
%define DNS_PORT 5353
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%define ELOOP_VAL 62
%define ENODATA_VAL 96
%else
%define SYS_write 1
%define SYS_exit  60
%define ELOOP_VAL 40
%define ENODATA_VAL 61
%endif

default rel

extern resolv_a, resolv_aaaa, resolv_a_all

global _start
global _main

section .rodata
n_aaaa:   db "libresolv-aaaa.test", 0
n_cname:  db "libresolv-cname.test", 0
n_loop:   db "libresolv-loop-a.test", 0
n_multi:  db "libresolv-multi.test", 0

; Expected: 2001:db8::42 as 16 network-order bytes.
exp_aaaa: db 0x20,0x01, 0x0d,0xb8, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0x42

; Expected: 203.0.113.42 as 4 net-order bytes.
exp_ok:   db 203, 0, 113, 42

; Expected multi-record set (packed as 12 bytes total).
exp_multi: db 203,0,113,1, 203,0,113,2, 203,0,113,3

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
ip4_buf:  resb 4
ip16_buf: resb 16
multi_buf: resb 64                  ; enough for 16 records × 4 bytes

section .text

_start:
_main:
    ; ---- 1: resolv_aaaa "libresolv-aaaa.test" ----
    mov byte [fail_id], '1'
    lea rdi, [n_aaaa]
    mov esi, 0x0100007F              ; 127.0.0.1
    mov edx, DNS_PORT
    lea rcx, [ip16_buf]
    call resolv_aaaa
    test rax, rax
    jnz .fail
    ; Compare 16 bytes.
    lea rdi, [ip16_buf]
    lea rsi, [exp_aaaa]
    mov ecx, 16
    call memeq
    test rax, rax
    jz .fail

    ; ---- 2: resolv_a with CNAME chase ----
    mov byte [fail_id], '2'
    lea rdi, [n_cname]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip4_buf]
    call resolv_a
    test rax, rax
    jnz .fail
    mov eax, [rel exp_ok]
    cmp eax, dword [ip4_buf]
    jne .fail

    ; ---- 3: CNAME hop-limit → -ELOOP ----
    mov byte [fail_id], '3'
    lea rdi, [n_loop]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip4_buf]
    call resolv_a
    cmp rax, -ELOOP_VAL
    jne .fail

    ; ---- 4: resolv_a_all with 3 records ----
    mov byte [fail_id], '4'
    lea rdi, [n_multi]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [multi_buf]
    mov r8d, 4                       ; capacity for up to 4 records
    call resolv_a_all
    cmp rax, 3
    jne .fail
    ; Compare 12 bytes.
    lea rdi, [multi_buf]
    lea rsi, [exp_multi]
    mov ecx, 12
    call memeq
    test rax, rax
    jz .fail

    ; ---- 5: resolv_a on an AAAA-only name → -ENODATA ----
    mov byte [fail_id], '5'
    lea rdi, [n_aaaa]
    mov esi, 0x0100007F
    mov edx, DNS_PORT
    lea rcx, [ip4_buf]
    call resolv_a
    cmp rax, -ENODATA_VAL
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
