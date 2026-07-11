; server-smoke.asm — server-side smoke test for libsock.a's
; listening / accepting path.
;
; Sequence: bind an AF_INET SOCK_STREAM socket to 127.0.0.1:0
; (kernel picks an ephemeral port), read the assigned port back
; via getsockname, print it to stdout as "PORT:<n>\n" so the
; harness can drive a client, verify via getsockopt(SO_TYPE)
; that the socket really is SOCK_STREAM, accept one client,
; verify via getpeername that the peer came in on 127.0.0.1,
; read the request, write the reply, cleanly shut down the
; write half so the client sees an orderly EOF, and close.
;
; Exercises: setsockopt, bind, listen, getsockname, getsockopt,
; accept, getpeername, shutdown — plus socket / close / read /
; write again as side effects. That covers every remaining
; libsock symbol not touched by ipc-smoke or tcp-smoke.
;
; Prints "FAIL:<id>\n" to stderr and exits 1 on the first
; failure. Sub-check ids:
;
;   1 socket()
;   2 setsockopt(SO_REUSEADDR)
;   3 bind()
;   4 listen()
;   5 getsockname() (learn assigned port)
;   6 getsockopt(SO_TYPE) returned SOCK_STREAM
;   7 accept()
;   8 getpeername() reports 127.0.0.1
;   9 read() the request
;   A write() the reply
;   B shutdown(SHUT_WR)
;   C close(client_fd)
;   D close(server_fd)

%define AF_INET      2
%define SOCK_STREAM  1
%define SHUT_WR      1

%ifdef MACOS
; From <sys/socket.h> on Darwin.
%define SOL_SOCKET   0xffff
%define SO_REUSEADDR 0x0004
%define SO_TYPE      0x1008
%else
; From /usr/include/asm-generic/socket.h on Linux.
%define SOL_SOCKET   1
%define SO_REUSEADDR 2
%define SO_TYPE      3
%endif

default rel

extern socket, setsockopt, bind, listen, getsockname, getsockopt
extern accept, getpeername, read, write, shutdown, close
extern htons, print_string, print_int, sys_exit

section .rodata
port_hdr:      db "PORT:"
port_hdr_len:  equ $ - port_hdr
nl:            db 10
reply:         db "SERVER-OK", 10
reply_len:     equ $ - reply

; See the note in ipc-smoke.asm — the fail message needs to live
; in a writable section because we overwrite the placeholder id.
section .data
fail_msg:      db "FAIL:?", 10
fail_id  equ fail_msg + 5
fail_len equ $ - fail_msg

section .bss
sa_local:      resb 16              ; sockaddr_in for bind / getsockname
sa_peer:       resb 16              ; sockaddr_in from accept / getpeername
sa_len:        resd 1               ; socklen_t in/out slot
so_val:        resd 1               ; getsockopt output value (int)
so_len:        resd 1               ; getsockopt socklen_t in/out
opt_one:       resd 1               ; setsockopt input value (int = 1)
req_buf:       resb 64              ; request receive buffer

section .text

global _start
global _main

_start:
_main:
    ; ---- 1: socket(AF_INET, SOCK_STREAM, 0) ----
    mov byte [fail_id], '1'
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov rbx, rax                     ; server_fd survives every later call

    ; ---- 2: setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt_one, 4)
    mov byte [fail_id], '2'
    mov dword [opt_one], 1
    mov rdi, rbx
    mov esi, SOL_SOCKET
    mov edx, SO_REUSEADDR
    lea rcx, [opt_one]
    mov r8d, 4
    call setsockopt
    test rax, rax
    js .fail

    ; Build sockaddr_in { AF_INET, sin_port=0, sin_addr=127.0.0.1 }.
    ; On macOS the first byte is sin_len (=16); the u16 header is
    ; 0x0210 (sin_len=16 low, sin_family=AF_INET=2 high). On Linux
    ; the u16 is just sin_family = 2.
%ifdef MACOS
    mov word [sa_local], 0x0210
%else
    mov word [sa_local], 0x0002
%endif
    mov word [sa_local + 2], 0
    mov dword [sa_local + 4], 0x0100007F
    mov qword [sa_local + 8], 0

    ; ---- 3: bind(server_fd, &sa_local, 16) ----
    mov byte [fail_id], '3'
    mov rdi, rbx
    lea rsi, [sa_local]
    mov edx, 16
    call bind
    test rax, rax
    js .fail

    ; ---- 4: listen(server_fd, 1) ----
    mov byte [fail_id], '4'
    mov rdi, rbx
    mov esi, 1
    call listen
    test rax, rax
    js .fail

    ; ---- 5: getsockname(server_fd, &sa_local, &sa_len) ----
    mov byte [fail_id], '5'
    mov dword [sa_len], 16
    mov rdi, rbx
    lea rsi, [sa_local]
    lea rdx, [sa_len]
    call getsockname
    test rax, rax
    js .fail

    ; Print "PORT:<n>\n" so the harness can point a client at us.
    ; sa_local + 2 is sin_port in network order — convert with a
    ; local byte swap (rather than calling htons) to keep this
    ; independent of the byte-order wrappers that ipc-smoke and
    ; inet4-smoke exercise.
    movzx r12, word [sa_local + 2]
    rol r12w, 8                      ; host-order port

    lea rdi, [port_hdr]
    mov rsi, port_hdr_len
    call print_string

    mov rdi, r12
    call print_int

    lea rdi, [nl]
    mov rsi, 1
    call print_string

    ; ---- 6: getsockopt(server_fd, SOL_SOCKET, SO_TYPE, &so_val, &so_len)
    mov byte [fail_id], '6'
    mov dword [so_len], 4
    mov rdi, rbx
    mov esi, SOL_SOCKET
    mov edx, SO_TYPE
    lea rcx, [so_val]
    lea r8, [so_len]
    call getsockopt
    test rax, rax
    js .fail
    cmp dword [so_val], SOCK_STREAM
    jne .fail

    ; ---- 7: accept(server_fd, &sa_peer, &sa_len) ----
    mov byte [fail_id], '7'
    mov dword [sa_len], 16
    mov rdi, rbx
    lea rsi, [sa_peer]
    lea rdx, [sa_len]
    call accept
    test rax, rax
    js .fail
    mov r13, rax                     ; client_fd

    ; ---- 8: getpeername(client_fd, &sa_peer, &sa_len) ----
    ; The peer must be 127.0.0.1 — anything else means someone
    ; slipped in on our loopback, or the kernel gave us a wrong
    ; address (e.g. we forgot to convert byte order).
    mov byte [fail_id], '8'
    mov dword [sa_len], 16
    mov rdi, r13
    lea rsi, [sa_peer]
    lea rdx, [sa_len]
    call getpeername
    test rax, rax
    js .fail
    cmp dword [sa_peer + 4], 0x0100007F
    jne .fail

    ; ---- 9: read(client_fd, req_buf, 64) ----
    mov byte [fail_id], '9'
    mov rdi, r13
    lea rsi, [req_buf]
    mov edx, 64
    call read
    test rax, rax
    jle .fail                        ; <0 error, 0 unexpected EOF

    ; ---- A: write(client_fd, reply, reply_len) ----
    mov byte [fail_id], 'A'
    mov rdi, r13
    lea rsi, [reply]
    mov edx, reply_len
    call write
    cmp rax, reply_len
    jne .fail

    ; ---- B: shutdown(client_fd, SHUT_WR) ----
    mov byte [fail_id], 'B'
    mov rdi, r13
    mov esi, SHUT_WR
    call shutdown
    test rax, rax
    js .fail

    ; ---- C: close(client_fd) ----
    mov byte [fail_id], 'C'
    mov rdi, r13
    call close
    test rax, rax
    jnz .fail

    ; ---- D: close(server_fd) ----
    mov byte [fail_id], 'D'
    mov rdi, rbx
    call close
    test rax, rax
    jnz .fail

    ; Success — sys_exit(0). No PASS printout: run.sh treats
    ; exit=0 as pass, and the earlier "PORT:<n>" line already
    ; identifies this binary in the log.
    xor edi, edi
    call sys_exit

.fail:
    ; Print the FAIL line straight to stderr via a raw write
    ; syscall — print_string in libasm goes to stdout, which the
    ; harness merges with the PORT line, and we want the failure
    ; identifier to stand out.
%ifdef MACOS
    mov rax, 0x2000004               ; SYS_write
%else
    mov rax, 1
%endif
    mov rdi, 2                       ; fd = stderr
    lea rsi, [fail_msg]
    mov rdx, fail_len
    syscall

    mov edi, 1
    call sys_exit
