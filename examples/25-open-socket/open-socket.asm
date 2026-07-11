; Open a TCP socket by calling socket() from libs/sock/libsock.a,
; then close it with close() from the same archive. Exit 0 on
; success, exit 1 if socket() returned a negative errno.
;
; Introduces linking against libsock and the `socket` syscall
; wrapper. Every later socket example builds on this base — bind,
; listen, accept, connect, and the read/write pair over a TCP
; connection all assume a live fd from socket() first.
;
; AF_INET and SOCK_STREAM are the same integer values on macOS
; and Linux (2 and 1 respectively), so no %ifdef branch is
; needed for the socket() call. The exit syscall number still
; differs per platform.

%ifdef MACOS
%define SYS_exit 0x2000001
%else
%define SYS_exit 60
%endif

%define AF_INET     2                   ; IPv4 address family
%define SOCK_STREAM 1                   ; reliable byte stream — TCP

default rel

extern socket, close

global _start
global _main

section .text

_start:
_main:
    ; socket(AF_INET, SOCK_STREAM, 0) — 0 picks TCP as the
    ; default protocol for the AF_INET / SOCK_STREAM pair.
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail                            ; -errno on failure
    mov ebx, eax                        ; save fd across close call

    ; close(fd) — the fd we just opened. Ignore the return
    ; value; there is nothing sensible to do if closing an fd
    ; we just made fails.
    mov edi, ebx
    call close

    ; exit(0)
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    ; exit(1)
    mov rax, SYS_exit
    mov edi, 1
    syscall
