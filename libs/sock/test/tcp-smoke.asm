; tcp-smoke.asm — end-to-end smoke test for libsock.a's TCP client path.
;
; Connects to a loopback server on 127.0.0.1:PORT, sends a short
; request, prints whatever the server sends back, and exits 0. Any
; syscall failure (negative errno in rax) exits 1. The harness in
; run.sh starts the server, assembles this file with -DPORT=<port>,
; links it against libsock.a + libasm.a, and asserts the reply.
;
; This is a test fixture, not part of the constructive examples/
; sequence — it lives under libs/sock/test/ next to the archive it
; exercises.

%ifndef PORT
%define PORT 8080                    ; default so the file assembles standalone
%endif

%define AF_INET     2
%define SOCK_STREAM 1

default rel

global _start
global _main

extern socket                        ; libs/sock/libsock.a
extern connect
extern read
extern write
extern close
extern htons
extern print_string                  ; libs/asm/libasm.a
extern sys_exit

section .rodata
req:     db "PING", 10               ; request payload (server ignores content)
req_len: equ $ - req

section .bss
buf:     resb 256                    ; reply buffer
sa:      resb 16                     ; sockaddr_in built at runtime

section .text

_start:
_main:
    ; fd = socket(AF_INET, SOCK_STREAM, 0)
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx                     ; protocol = 0 (default TCP)
    call socket
    test rax, rax
    js .fail
    mov rbx, rax                     ; save fd across later calls (callee-saved)

    ; Build sockaddr_in at [sa]:
    ;   macOS: [sin_len=16][sin_family=AF_INET] = 0x0210 as u16 LE
    ;   Linux: [sin_family=AF_INET as u16 LE]   = 0x0002
    ;   [sin_port = htons(PORT)]
    ;   [sin_addr = 127.0.0.1 in network byte order = 0x0100007F LE]
    ;   [sin_zero = 8 zero bytes]
%ifdef MACOS
    mov word [sa], 0x0210
%else
    mov word [sa], 0x0002
%endif
    mov edi, PORT
    call htons                       ; rax = htons(PORT), upper bits zero
    mov [sa + 2], ax
    mov dword [sa + 4], 0x0100007F   ; 127.0.0.1 already in network byte order
    mov qword [sa + 8], 0            ; sin_zero

    ; connect(fd, &sa, 16)
    mov rdi, rbx
    lea rsi, [sa]
    mov edx, 16                      ; sizeof(sockaddr_in)
    call connect
    test rax, rax
    js .fail

    ; write(fd, req, req_len)
    mov rdi, rbx
    lea rsi, [req]
    mov edx, req_len
    call write
    test rax, rax
    js .fail

    ; read(fd, buf, 256) — expect the server's banner
    mov rdi, rbx
    lea rsi, [buf]
    mov edx, 256
    call read
    test rax, rax
    js .fail
    mov r12, rax                     ; bytes received

    ; print_string(buf, r12)
    lea rdi, [buf]
    mov rsi, r12
    call print_string

    ; close(fd) — best effort; ignore result
    mov rdi, rbx
    call close

    xor edi, edi                     ; exit status = 0 (success)
    call sys_exit

.fail:
    mov edi, 1                       ; exit status = 1 (a syscall failed)
    call sys_exit
