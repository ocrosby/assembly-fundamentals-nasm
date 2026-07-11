; Open a TCP socket via libs/sock/libsock.a, bind it to
; 127.0.0.1:0 (loopback, kernel picks the port), then mark it
; passive with listen() so it is ready to accept incoming
; connections — and finally close the fd. Exit 0 on success;
; exit 1 if any syscall returned a negative errno.
;
; Introduces listen(fd, backlog) — the step that turns a bound
; socket into a passive listener. Between bind (26) and accept
; (a future example), listen is the state transition that
; makes the socket eligible to answer a client.
;
; Nothing observable happens after listen because the program
; closes immediately — no client is around to connect. Later
; examples add accept() and read/write over the connection.

%ifdef MACOS
%define SYS_exit    0x2000001
%define SIN_HEADER  0x0210          ; sin_len=16, sin_family=AF_INET (little-endian)
%else
%define SYS_exit    60
%define SIN_HEADER  0x0002          ; sin_family=AF_INET as u16
%endif

%define AF_INET      2
%define SOCK_STREAM  1
%define BACKLOG      8               ; how many pending connections the kernel
                                    ; will queue before returning ECONNREFUSED
                                    ; to new clients. 8 is enough to make the
                                    ; behavior distinguishable without being
                                    ; wasteful.

default rel

extern socket, bind, listen, close

global _start
global _main

section .rodata
sockaddr_in:
    dw SIN_HEADER               ; sin_family (+ sin_len on macOS)
    dw 0                        ; sin_port = 0 (kernel picks)
    db 127, 0, 0, 1             ; sin_addr = 127.0.0.1, network order
    dq 0                        ; sin_zero

section .text

_start:
_main:
    ; socket(AF_INET, SOCK_STREAM, 0)
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov ebx, eax

    ; bind(fd, sockaddr_in*, 16)
    mov edi, ebx
    lea rsi, [sockaddr_in]
    mov edx, 16
    call bind
    test rax, rax
    js .fail

    ; listen(fd, BACKLOG) — the new syscall this example
    ; introduces. After this call the socket is a passive
    ; listener; accept() would return the next queued
    ; connection.
    mov edi, ebx
    mov esi, BACKLOG
    call listen
    test rax, rax
    js .fail

    ; close(fd)
    mov edi, ebx
    call close

    ; exit(0)
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
