; Fork a parent/child pair that talk to each other over a TCP
; loopback socket in a single process image. Parent listens
; and reads; child connects and writes "PING". Exit 0 on
; success — proves the full accept/connect + read/write cycle
; wires end-to-end.
;
; Introduces the first payoff of the socket-and-process
; sequence: combining libsock (25/26/27) with libproc (28) to
; move real bytes between two processes without any external
; tool. Every earlier socket example ended at a state
; transition (opened / bound / listening) with nothing to
; talk to; this one has a peer built in.
;
; Program flow:
;
;   1. socket(AF_INET, SOCK_STREAM, 0)          — listener fd
;   2. bind(fd, 127.0.0.1:0)                    — kernel picks port
;   3. getsockname(fd, out, &len)               — read the port back
;   4. Copy the resolved port into client_sockaddr[sin_port]
;   5. listen(fd, 1)                            — accept queue length 1
;   6. fork()
;      6a. Child branch: close listener, socket, connect to
;          the picked port, write "PING", close, _exit(0).
;      6b. Parent branch: accept, read 4 bytes, verify they
;          are "PING", close both fds, wait4 the child,
;          require its wstatus == 0, exit(0).
;
; The kernel queues the child's connect on the listen backlog
; even if the parent is not yet in accept() — so the code does
; not need to synchronize the two branches, and there is no
; sleep in the child. Any error along either path exits 1.

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

; "PING" as a little-endian dword. `db "PING"` puts bytes
; 0x50, 0x49, 0x4E, 0x47 in memory, which read as a dword
; little-endian gives 0x474E4950.
%define PING_LE  0x474E4950

default rel

extern socket, bind, listen, accept, connect, read, write, close
extern getsockname
extern fork, wait4

global _start
global _main

section .data
; Listener sockaddr — port 0 asks the kernel to pick a free
; ephemeral port that getsockname will read back below.
listen_sockaddr:
    dw SIN_HEADER               ; sin_family (+ sin_len on macOS)
    dw 0                        ; sin_port (kernel picks)
    db 127, 0, 0, 1             ; sin_addr = 127.0.0.1 (network order)
    dq 0                        ; sin_zero

; Client sockaddr — sin_port gets patched at runtime from the
; resolved listener port. Same 16-byte layout.
client_sockaddr:
    dw SIN_HEADER
    dw 0                        ; overwritten with real port
    db 127, 0, 0, 1
    dq 0

msg:     db "PING"
msg_len: equ $ - msg

section .bss
addrlen: resd 1
recvbuf: resb 4
wstatus: resq 1

section .text

_start:
_main:
    ; ---- 1: socket() ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov ebx, eax                    ; listener fd (callee-saved)

    ; ---- 2: bind() ----
    mov edi, ebx
    lea rsi, [listen_sockaddr]
    mov edx, 16
    call bind
    test rax, rax
    js .fail

    ; ---- 3: getsockname() — read the kernel-assigned port ----
    ; addrlen is both an input (buffer size) and output (bytes
    ; actually written). Reset it to 16 before every call.
    mov dword [addrlen], 16
    mov edi, ebx
    lea rsi, [listen_sockaddr]
    lea rdx, [addrlen]
    call getsockname
    test rax, rax
    js .fail

    ; ---- 4: patch the port into client_sockaddr ----
    ; Both sockaddr_in structures store sin_port at offset 2 in
    ; network byte order. The 16 raw bits copy without any
    ; endianness gymnastics.
    mov ax, [listen_sockaddr + 2]
    mov [client_sockaddr + 2], ax

    ; ---- 5: listen() ----
    mov edi, ebx
    mov esi, BACKLOG
    call listen
    test rax, rax
    js .fail

    ; ---- 6: fork() ----
    call fork
    test rax, rax
    js .fail
    jz .child

    ; ================================================================
    ; Parent branch
    ; ================================================================
    mov r13d, eax                   ; child pid (callee-saved)

    ; accept(listener, NULL, NULL) — take the incoming connection
    mov edi, ebx
    xor esi, esi                    ; addr = NULL
    xor edx, edx                    ; addrlen = NULL
    call accept
    test rax, rax
    js .fail
    mov r12d, eax                   ; accepted-connection fd

    ; read(accepted_fd, recvbuf, 4) — expect exactly 4 bytes.
    ; The child sends exactly "PING" then closes, so read
    ; returns 4 without needing to wait for EOF.
    mov edi, r12d
    lea rsi, [recvbuf]
    mov edx, 4
    call read
    cmp rax, 4
    jne .fail

    ; Verify recvbuf == "PING"
    cmp dword [recvbuf], PING_LE
    jne .fail

    ; Close both fds — connected first, then listener.
    mov edi, r12d
    call close
    mov edi, ebx
    call close

    ; wait4(child_pid, &wstatus, 0, NULL) — reap the child.
    mov edi, r13d
    lea rsi, [wstatus]
    xor edx, edx                    ; options = 0
    xor ecx, ecx                    ; rusage = NULL
    call wait4
    test rax, rax
    js .fail

    ; wstatus == 0 iff the child exited(0). Any nonzero value
    ; signals a child-side failure (bad connect, short write,
    ; or a signal) that this test wants to catch.
    mov rax, [wstatus]
    test rax, rax
    jnz .fail

    ; exit(0)
    mov rax, SYS_exit
    xor edi, edi
    syscall

    ; ================================================================
    ; Child branch
    ; ================================================================
.child:
    ; Close the inherited listener fd. The child does not need
    ; it — production child processes drop unused fds anyway,
    ; and here it keeps the kernel's per-socket reference count
    ; clean.
    mov edi, ebx
    call close

    ; socket() — the client-side endpoint.
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .fail
    mov r12d, eax                   ; client fd

    ; connect(fd, client_sockaddr, 16) — client_sockaddr's port
    ; was patched with the resolved listener port before fork,
    ; so the child sees it via the copy-on-write image.
    mov edi, r12d
    lea rsi, [client_sockaddr]
    mov edx, 16
    call connect
    test rax, rax
    js .fail

    ; write "PING"
    mov edi, r12d
    lea rsi, [msg]
    mov edx, msg_len
    call write
    cmp rax, msg_len
    jne .fail

    ; close + _exit(0)
    mov edi, r12d
    call close
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
