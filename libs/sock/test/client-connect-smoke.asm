; client-connect-smoke.asm — end-to-end loopback smoke for the
; util helpers. Runs entirely in one process without a Python
; peer: the TCP three-way handshake completes in the kernel's
; listen queue as soon as connect() sends its ACK, so accept()
; returns immediately without needing a separate thread.
;
; Sequence:
;
;   1  server_bind_listen(INADDR_ANY, 0, 1)     → server_fd
;   2  getsockname(server_fd)                   → 0 (learn port)
;   3  client_connect(127.0.0.1, port)          → client_fd
;   4  accept(server_fd, NULL, NULL)            → accepted_fd
;   5  close(client_fd)                         → 0
;   6  close(accepted_fd)                       → 0
;   7  close(server_fd)                         → 0
;   8  client_connect(127.0.0.1, port=1)        → negative
;      (nothing listens on port 1 — the connect must fail,
;       which also exercises the helper's close-on-fail path)

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

extern server_bind_listen, client_connect
extern accept, getsockname

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
; sockaddr_in that getsockname writes into; sockaddr_len is the
; in-out length parameter.
sockaddr:    resb 16
sockaddr_len: resd 1

section .text

_start:
_main:
    ; ---- 1: server_bind_listen(0, 0, 1) → positive fd ----
    mov byte [fail_id], '1'
    xor edi, edi                     ; INADDR_ANY
    xor esi, esi                     ; kernel picks port
    mov edx, 1                        ; backlog = 1
    call server_bind_listen
    test rax, rax
    js .fail
    mov r13, rax                     ; server_fd

    ; ---- 2: getsockname(server_fd, &sockaddr, &sockaddr_len) → 0 ----
    mov byte [fail_id], '2'
    mov dword [sockaddr_len], 16
    mov rdi, r13
    lea rsi, [sockaddr]
    lea rdx, [sockaddr_len]
    call getsockname
    test rax, rax
    jnz .fail

    ; ---- 3: client_connect(127.0.0.1, port) → positive fd ----
    ; Read sockaddr[2..3] as a big-endian u16 and swap into
    ; host order for client_connect (which takes port_host).
    mov byte [fail_id], '3'
    movzx esi, word [sockaddr + 2]
    rol si, 8                        ; net → host
    mov edi, 0x0100007F              ; 127.0.0.1 in network byte order
    call client_connect
    test rax, rax
    js .fail
    mov r14, rax                     ; client_fd

    ; ---- 4: accept(server_fd, NULL, NULL) → positive fd ----
    ; The handshake completed inside client_connect's
    ; connect(2), so the accept queue already has an entry —
    ; accept returns immediately, no threading needed.
    mov byte [fail_id], '4'
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    call accept
    test rax, rax
    js .fail
    mov r15, rax                     ; accepted_fd

    ; ---- 5: close(client_fd) ----
    mov byte [fail_id], '5'
    mov rdi, r14
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_c_ok
    neg rax
.close_c_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- 6: close(accepted_fd) ----
    mov byte [fail_id], '6'
    mov rdi, r15
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_a_ok
    neg rax
.close_a_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- 7: close(server_fd) ----
    mov byte [fail_id], '7'
    mov rdi, r13
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_s_ok
    neg rax
.close_s_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- 8: client_connect to a port nothing listens on → < 0 ----
    ; Also exercises the helper's close-on-fail path: connect
    ; fails with -ECONNREFUSED, the fd must be closed before
    ; returning. If it weren't, the process would leak an fd
    ; each attempt.
    mov byte [fail_id], '8'
    mov edi, 0x0100007F
    mov esi, 1                       ; port 1 — nothing listens
    call client_connect
    test rax, rax
    jns .fail                        ; want strictly negative

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
