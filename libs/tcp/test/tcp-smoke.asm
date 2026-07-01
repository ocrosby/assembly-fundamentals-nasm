; tcp-smoke.asm — end-to-end smoke test for libtcp.a.
;
; Connects to a loopback server on 127.0.0.1:PORT, sends a short
; request, prints whatever the server sends back, and exits 0. Any
; syscall failure (negative errno in rax) exits 1. The harness in
; run.sh starts the server, assembles this file with -DPORT=<port>,
; links it against libtcp.a + libasm.a, and asserts the reply.
;
; This is a test fixture, not part of the constructive examples/
; sequence — it lives under libs/tcp/test/ next to the archive it
; exercises.

%ifndef PORT
%define PORT 8080                    ; default so the file assembles standalone
%endif

default rel

global _start
global _main

extern tcp_connect                   ; libs/tcp/libtcp.a
extern tcp_send
extern tcp_recv
extern tcp_close
extern print_string                  ; libs/asm/libasm.a
extern sys_exit

section .rodata
req:     db "PING", 10               ; request payload (server ignores content)
req_len: equ $ - req

section .bss
buf:     resb 256                    ; reply buffer

section .text

_start:
_main:
    mov edi, 0x0100007F              ; 127.0.0.1 (u32, network byte order)
    mov esi, PORT                    ; port, host order — tcp_connect byte-swaps
    call tcp_connect                 ; rax = fd or negative errno
    test rax, rax
    js .fail
    mov rbx, rax                     ; fd (callee-saved: survives later calls)

    mov rdi, rbx                     ; arg 1: fd
    lea rsi, [req]                   ; arg 2: buffer
    mov edx, req_len                 ; arg 3: length
    call tcp_send                    ; rax = bytes written or negative errno
    test rax, rax
    js .fail

    mov rdi, rbx                     ; arg 1: fd
    lea rsi, [buf]                   ; arg 2: buffer
    mov edx, 256                     ; arg 3: capacity
    call tcp_recv                    ; rax = bytes read, 0 = EOF, or -errno
    test rax, rax
    js .fail
    mov r12, rax                     ; bytes received

    lea rdi, [buf]                   ; arg 1: buffer
    mov rsi, r12                     ; arg 2: length
    call print_string                ; echo the reply to stdout

    mov rdi, rbx                     ; arg 1: fd
    call tcp_close                   ; best effort; ignore result

    xor edi, edi                     ; exit status = 0 (success)
    call sys_exit

.fail:
    mov edi, 1                       ; exit status = 1 (a syscall failed)
    call sys_exit
