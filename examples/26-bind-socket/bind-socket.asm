; Open a TCP socket and bind it to 127.0.0.1:0 (loopback, any
; free port) via libs/sock/libsock.a's socket() and bind()
; wrappers, then close the fd. Exit 0 on success; exit 1 if
; socket() or bind() returned a negative errno.
;
; Introduces the manual construction of a `struct sockaddr_in`
; and the bind() syscall — the step 25-open-socket deliberately
; skipped. Every later socket example builds on this base:
; listen turns the bound socket into a passive listener, accept
; blocks for an incoming connection, connect initiates one.
;
; sockaddr_in layout (16 bytes, with a per-platform difference
; in the first two bytes — BSD systems carry an extra sin_len
; field at offset 0):
;
;   offset 0 (macOS): sin_len   = 16
;   offset 1 (macOS): sin_family = AF_INET  (2)
;   offset 0 (Linux): sin_family = AF_INET (u16)
;   offset 2:         sin_port  (u16, network byte order)
;   offset 4:         sin_addr  (u32, network byte order)
;   offset 8:         sin_zero  (8 bytes of padding)
;
; Little-endian storage means that writing sin_family alone as
; a u16 (Linux) or the {sin_len, sin_family} pair as a u16
; (macOS) collapses to a single `dw` with a per-platform value.

%ifdef MACOS
%define SYS_exit    0x2000001
%define SIN_HEADER  0x0210          ; sin_len=16, sin_family=AF_INET (little-endian)
%else
%define SYS_exit    60
%define SIN_HEADER  0x0002          ; sin_family=AF_INET as u16
%endif

%define AF_INET      2               ; IPv4 address family
%define SOCK_STREAM  1               ; reliable byte stream — TCP

default rel

extern socket, bind, close

global _start
global _main

section .rodata
; sockaddr_in for 127.0.0.1:0. sin_addr is written byte-by-byte
; in network order so the numeric value is unambiguous — no
; mental gymnastics around htonl.
sockaddr_in:
    dw SIN_HEADER               ; sin_family (+ sin_len on macOS)
    dw 0                        ; sin_port = 0 (ask kernel to pick a free port)
    db 127, 0, 0, 1             ; sin_addr = 127.0.0.1, network order
    dq 0                        ; sin_zero

section .text

_start:
_main:
    ; socket(AF_INET, SOCK_STREAM, 0) — 0 selects TCP as the
    ; default protocol for this domain/type.
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov ebx, eax                ; save fd across bind + close

    ; bind(fd, sockaddr_in*, 16). The addrlen is exactly the
    ; sockaddr_in size, not a "how much of the struct is used"
    ; hint — bind reads exactly this many bytes.
    mov edi, ebx
    lea rsi, [sockaddr_in]
    mov edx, 16
    call bind
    test rax, rax
    js .fail

    ; close(fd). If the process exited without close, the
    ; kernel would clean up anyway, but calling close is the
    ; explicit form and mirrors what every real server does.
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
