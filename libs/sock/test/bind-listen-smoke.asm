; bind-listen-smoke.asm — smoke test for util/server_bind_listen.
;
; Standalone: no Python peer, no network traffic. Just proves the
; composed helper is a drop-in replacement for the four-syscall
; server prologue and cleans up properly on the caller's behalf.
;
; Sub-check ids:
;
;   1  server_bind_listen(INADDR_ANY, port=0, backlog=5)
;      → positive fd; kernel picks the port
;   2  close(fd_from_1)
;   3  server_bind_listen(127.0.0.1, port=0, backlog=1)
;      → positive fd; loopback bind works via the ip_net argument
;   4  close(fd_from_3)

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%define SYS_close 0x2000006
%else
%define SYS_write 1
%define SYS_exit  60
%define SYS_close 3
%endif

default rel

extern server_bind_listen

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .text

_start:
_main:
    ; ---- 1: server_bind_listen(0, 0, 5) → positive fd ----
    mov byte [fail_id], '1'
    xor edi, edi                     ; INADDR_ANY
    xor esi, esi                     ; port_host = 0 (kernel picks)
    mov edx, 5                        ; backlog
    call server_bind_listen
    test rax, rax
    js .fail
    mov rbx, rax                     ; save fd

    ; ---- 2: close(fd) ----
    mov byte [fail_id], '2'
    mov rdi, rbx
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close1_ok
    neg rax
.close1_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- 3: server_bind_listen(127.0.0.1, 0, 1) → positive fd ----
    mov byte [fail_id], '3'
    mov edi, 0x0100007F              ; 127.0.0.1 in network order
                                     ; (0x7F 0x00 0x00 0x01 as bytes)
    xor esi, esi
    mov edx, 1
    call server_bind_listen
    test rax, rax
    js .fail
    mov rbx, rax

    ; ---- 4: close(fd) ----
    mov byte [fail_id], '4'
    mov rdi, rbx
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close2_ok
    neg rax
.close2_ok:
%endif
    test rax, rax
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
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall
