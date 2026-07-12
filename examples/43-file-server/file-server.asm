; Serve a file over a TCP socket with `file_copy_stream`.
; The parent seeds "HELLO WORLD!" into /tmp/nasm-file-server.txt,
; binds a loopback listener, forks. The child accepts one
; connection, calls `file_copy_stream(path, conn_fd)`, and
; exits. The parent connects to the same port, reads until EOF,
; byte-compares against the reference, and exits 42 on
; success.
;
; First runnable that combines libio v1.15 (`file_copy_stream`)
; with a libsock server. Where 41-logger and 39-number-store
; kept the writes on a local file, this example proves the
; helper's second use case: sending a file over a
; caller-provided fd — the "send this file over this socket"
; pattern that motivated shipping `file_copy_stream`.
;
; Coordination follows 29-server-client / 34-echo-server:
; bind before fork, `getsockname` to read the resolved port,
; patch the client sockaddr, then fork so both sides share
; the same port constant.
;
; Program flow:
;
;   parent:
;     file_write_all(path, "HELLO WORLD!", 12)  ; seed
;     socket, bind, getsockname, listen         ; listener fd = ebx
;     fork()
;     ├── child (server):
;     │      accept()                            ; conn_fd
;     │      file_copy_stream(path, conn_fd)
;     │      close(conn_fd); close(listener)
;     │      exit(0)
;     └── parent (client):
;            socket, connect
;            loop read into buf until 12 bytes received
;            byte-compare buf vs "HELLO WORLD!"
;            wait4(child)
;            exit(42)

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
%define BUF_SIZE     32

default rel

extern socket, bind, listen, accept, connect, close
extern read, getsockname
extern fork, wait4
extern file_write_all, file_copy_stream

global _start
global _main

section .rodata
path:     db "/tmp/nasm-file-server.txt", 0
msg:      db "HELLO WORLD!"
msg_len:  equ $ - msg               ; 12

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
    dw 0                             ; overwritten with resolved port
    db 127, 0, 0, 1
    dq 0

section .bss
addrlen: resd 1
buf:     resb BUF_SIZE
wstatus: resq 1

section .text

_start:
_main:
    ; ---- Seed the fixture ----
    ; The file existing before the fork is what the child
    ; will end up sending over the socket. file_write_all
    ; guarantees a clean slate even if a previous run left
    ; content behind.
    lea rdi, [path]
    lea rsi, [msg]
    mov rdx, msg_len
    call file_write_all
    test rax, rax
    jnz .fail

    ; ---- socket + bind + getsockname + listen ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov ebx, eax                     ; listener fd (callee-saved)

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

    ; Copy the resolved port from listen_sockaddr[2..4] into
    ; client_sockaddr[2..4]. Both are network order — the
    ; raw bytes copy unchanged.
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
    ; Parent — client role. Connect, read the file back, verify.
    ; ================================================================
    mov r13d, eax                    ; child pid

    ; socket + connect
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov r12d, eax                    ; client fd

    mov edi, r12d
    lea rsi, [client_sockaddr]
    mov edx, 16
    call connect
    test rax, rax
    js .fail

    ; ---- Read loop: pull msg_len bytes ----
    ; Short reads are the caller's problem on the receiver
    ; side — the child's file_copy_stream honors its short-
    ; write loop, but the socket layer can still split the
    ; transfer into multiple TCP segments.
    xor r14d, r14d                   ; bytes received
.recv_loop:
    mov edi, r12d
    lea rsi, [buf]
    add rsi, r14                     ; buf + offset
    mov edx, BUF_SIZE
    sub edx, r14d
    call read
    test rax, rax
    jle .fail                        ; EOF too early or -errno
    add r14, rax
    cmp r14, msg_len
    jb .recv_loop

    ; ---- Byte-compare against msg ----
    ; Spelled out as a loop so this example does not force
    ; libstr into the link line.
    lea r9, [buf]
    lea r10, [msg]
    xor rcx, rcx
.cmp_loop:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, msg_len
    jb .cmp_loop

    ; ---- Close the client fd, reap the child ----
    mov edi, r12d
    call close

    mov edi, r13d
    lea rsi, [wstatus]
    xor edx, edx
    xor ecx, ecx
    call wait4
    test rax, rax
    js .fail

    ; Verify the child exited cleanly. wstatus low 7 bits == 0
    ; means normal exit; (wstatus >> 8) & 0xff is the code.
    mov eax, [wstatus]
    test eax, 0x7f                   ; low 7 bits should be 0
    jnz .fail
    sar eax, 8
    and eax, 0xff
    test eax, eax
    jnz .fail

    mov edi, ebx
    call close

    ; exit(42)
    mov rax, SYS_exit
    mov edi, 42
    syscall

    ; ================================================================
    ; Child — server role. Accept one connection, send the file.
    ; ================================================================
.child:
    ; Accept the parent's incoming connection.
    mov edi, ebx
    xor esi, esi
    xor edx, edx
    call accept
    test rax, rax
    js .child_fail
    mov r12d, eax                    ; conn fd

    ; file_copy_stream(path, conn_fd). The helper opens the
    ; source, mmaps it, drains size bytes into conn_fd via a
    ; short-write loop, unmaps, and returns 0 on success.
    lea rdi, [path]
    mov esi, r12d
    call file_copy_stream
    test rax, rax
    jnz .child_fail

    ; Close both fds. The parent's `read` returns EOF once the
    ; TCP peer closes; that is how the parent knows the
    ; transfer finished when file_copy_stream doesn't itself
    ; frame the message.
    mov edi, r12d
    call close
    mov edi, ebx
    call close

    ; _exit(0) — signal clean success to the parent's wait4.
    mov rax, SYS_exit
    xor edi, edi
    syscall

.child_fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
