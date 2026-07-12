; A single-process TCP echo server. Parent listens on
; 127.0.0.1:0, forks a client child, then runs an echo loop
; against whatever the child sends. Child sends
; "HELLO WORLD!", reads it back, verifies, closes. Parent
; sees EOF, closes, wait4s the child, exits 42.
;
; Builds on [29-server-client](../29-server-client/) — 29 did
; a single-round-trip PING. This example adds two new things:
;
;   1. An actual read → send_all loop on the parent side.
;      Once the child closes, the parent's read returns 0
;      (EOF) and the loop exits. That is what turns a
;      one-shot exchange into a real echo server.
;   2. First use of libsock v1.4's `send_all` composed
;      helper. `write` on a socket can (and eventually will)
;      accept fewer bytes than requested — `send_all` factors
;      the "keep writing until the whole payload is on the
;      wire" loop out of the caller.
;
; Same port-coordination trick as 29: bind loopback:0, ask
; the kernel to pick, use `getsockname` to read the resolved
; port back, patch it into the client sockaddr, THEN fork.
; The child inherits the patched sockaddr via copy-on-write.

%ifdef MACOS
%define SYS_exit    0x2000001
%define SIN_HEADER  0x0210          ; sin_len=16, sin_family=AF_INET
%else
%define SYS_exit    60
%define SIN_HEADER  0x0002          ; sin_family=AF_INET as u16
%endif

%define AF_INET      2
%define SOCK_STREAM  1
%define BACKLOG      1
%define BUF_SIZE     64

; "HELLO WORLD!" — 12 bytes. Compared in the child as three
; little-endian dwords instead of a byte loop. Layout:
;   bytes  0..3 = 'H','E','L','L' (0x48,0x45,0x4C,0x4C) → 0x4C4C4548
;   bytes  4..7 = 'O',' ','W','O' (0x4F,0x20,0x57,0x4F) → 0x4F57204F
;   bytes  8..11= 'R','L','D','!' (0x52,0x4C,0x44,0x21) → 0x21444C52
%define HELLO_DW0    0x4C4C4548
%define HELLO_DW1    0x4F57204F
%define HELLO_DW2    0x21444C52

default rel

extern socket, bind, listen, accept, connect, close
extern read, send_all
extern getsockname
extern fork, wait4

global _start
global _main

section .data
; Listener sockaddr — port 0 asks the kernel to pick a free
; port that getsockname reads back below.
listen_sockaddr:
    dw SIN_HEADER
    dw 0
    db 127, 0, 0, 1
    dq 0

client_sockaddr:
    dw SIN_HEADER
    dw 0                        ; overwritten with resolved port
    db 127, 0, 0, 1
    dq 0

section .rodata
msg:     db "HELLO WORLD!"
msg_len: equ $ - msg

section .bss
addrlen: resd 1
buf:     resb BUF_SIZE
wstatus: resq 1

section .text

_start:
_main:
    ; ---- socket + bind + getsockname + listen ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov ebx, eax                    ; listener fd (callee-saved)

    mov edi, ebx
    lea rsi, [listen_sockaddr]
    mov edx, 16
    call bind
    test rax, rax
    js .fail

    mov dword [addrlen], 16
    mov edi, ebx
    lea rsi, [listen_sockaddr]
    lea rdx, [addrlen]
    call getsockname
    test rax, rax
    js .fail

    ; Copy the resolved port from listen_sockaddr[2..4]
    ; into client_sockaddr[2..4]. Both are network order —
    ; the raw bytes copy unchanged.
    mov ax, [listen_sockaddr + 2]
    mov [client_sockaddr + 2], ax

    mov edi, ebx
    mov esi, BACKLOG
    call listen
    test rax, rax
    js .fail

    ; ---- fork ----
    call fork
    test rax, rax
    js .fail
    jz .child

    ; ================================================================
    ; Parent — echo server loop
    ; ================================================================
    mov r13d, eax                   ; child pid

    ; accept — take the child's incoming connection.
    mov edi, ebx
    xor esi, esi
    xor edx, edx
    call accept
    test rax, rax
    js .fail
    mov r12d, eax                   ; connected fd (callee-saved)

    ; ---- echo loop ----
    ; Read up to BUF_SIZE bytes. On EOF (rax == 0) exit the
    ; loop. On error (rax < 0) fail. Otherwise send_all the
    ; bytes back.
.echo_loop:
    mov edi, r12d
    lea rsi, [buf]
    mov edx, BUF_SIZE
    call read
    test rax, rax
    jz .echo_done                   ; EOF
    js .fail                        ; -errno

    ; send_all(fd, buf, rax) — echo exactly the bytes we read.
    mov rdx, rax                    ; len from read's return
    mov edi, r12d
    lea rsi, [buf]
    call send_all
    test rax, rax
    jnz .fail                       ; non-zero = error
    jmp .echo_loop

.echo_done:
    ; ---- Clean up + reap child + exit ----
    mov edi, r12d
    call close
    mov edi, ebx
    call close

    mov edi, r13d
    lea rsi, [wstatus]
    xor edx, edx
    xor ecx, ecx
    call wait4
    test rax, rax
    js .fail

    mov rax, [wstatus]
    test rax, rax
    jnz .fail                       ; child must have exited 0

    ; exit(42) — distinctive success marker.
    mov rax, SYS_exit
    mov edi, 42
    syscall

    ; ================================================================
    ; Child — talk to the parent's server
    ; ================================================================
.child:
    ; Close the inherited listener fd.
    mov edi, ebx
    call close

    ; socket + connect
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov r12d, eax                   ; client fd

    mov edi, r12d
    lea rsi, [client_sockaddr]
    mov edx, 16
    call connect
    test rax, rax
    js .fail

    ; send_all "HELLO WORLD!"
    mov edi, r12d
    lea rsi, [msg]
    mov edx, msg_len
    call send_all
    test rax, rax
    jnz .fail

    ; read exactly msg_len bytes back. Loop in case of a
    ; short read — same pattern parent's echo loop uses on
    ; the receive side.
    mov r13d, msg_len               ; bytes remaining
    xor r14d, r14d                  ; offset into buf
.recv_loop:
    mov edi, r12d
    lea rsi, [buf]
    add rsi, r14                    ; buf + offset
    mov edx, r13d
    call read
    test rax, rax
    jle .fail                       ; 0 (EOF too early) or -errno
    add r14, rax
    sub r13, rax
    jnz .recv_loop

    ; Verify "HELLO WORLD!" — three dword compares.
    ; buf layout: 'H','E','L','L' | 'O',' ','W','O' | 'R','L','D','!'
    cmp dword [buf + 0], HELLO_DW0
    jne .fail
    cmp dword [buf + 4], HELLO_DW1
    jne .fail
    cmp dword [buf + 8], HELLO_DW2
    jne .fail

    ; close + _exit(0) — closing the write side sends FIN,
    ; which makes the parent's read return 0 and end the
    ; echo loop.
    mov edi, r12d
    call close
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
