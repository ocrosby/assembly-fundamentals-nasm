; server_bind_listen(ip_net, port_host, backlog) -> rax = server_fd or -errno
;
; Compose the four syscalls every TCP server always makes into a
; single call. Equivalent to:
;
;     fd = socket(AF_INET, SOCK_STREAM, 0)
;     setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &1, 4)
;     bind(fd, sockaddr_in{ip, port}, 16)
;     listen(fd, backlog)
;
; Argument shape:
;   rdi = ip_net    — u32 IPv4 in network byte order. Pass 0
;                     (INADDR_ANY) to bind every interface,
;                     0x0100007F for 127.0.0.1 on little-endian
;                     x86_64, etc.
;   rsi = port_host — u16 port in host byte order. Pass 0 to let
;                     the kernel pick an ephemeral port; the
;                     caller retrieves it via getsockname on the
;                     returned fd.
;   rdx = backlog   — int, the listen(2) backlog.
;
; Returns:
;   rax >= 0        — the newly created server_fd, ready to accept.
;   rax < 0         — an errno. On any post-socket failure the fd
;                     is closed before returning so the caller
;                     never leaks a descriptor.
;
; Stack layout (24 bytes, 16-aligned before every nested call):
;   [rsp+0..15]   sockaddr_in (16 bytes)
;   [rsp+16..23] errno save slot (used only on the close-and-fail
;                path so the close's return value doesn't clobber
;                the failing errno)
;
; Register roles:
;   rbx  = server_fd (survives all nested calls; must be popped)
;   rbp  = backlog spill (preserved across socket + setsockopt +
;          bind before listen consumes it)

%include "syscall.inc"

default rel

extern socket, setsockopt, bind, listen, close

global server_bind_listen

section .text

server_bind_listen:
    push rbx
    push rbp
    sub rsp, 24

    mov ebp, edx                    ; backlog

    ; Build sockaddr_in at [rsp+0..15]:
    ;   +0..1  sin_len + sin_family (SIN_HEADER — one const per platform)
    ;   +2..3  sin_port (network byte order)
    ;   +4..7  sin_addr (already network byte order per contract)
    ;   +8..15 sin_zero
    mov word [rsp + 0], SIN_HEADER
    mov ax, si                      ; port_host (low 16 bits of rsi)
    rol ax, 8                       ; host → network
    mov [rsp + 2], ax
    mov [rsp + 4], edi              ; ip_net (already net-order per contract)
    mov qword [rsp + 8], 0          ; sin_zero

    ; ---- 1: socket(AF_INET, SOCK_STREAM, 0) ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .done                        ; -errno passes through
    mov rbx, rax                    ; server_fd

    ; ---- 2: setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, 4) ----
    ; The option value is a 4-byte int of 1; use the errno slot
    ; as scratch — it isn't holding an errno yet.
    mov dword [rsp + 16], 1
    mov rdi, rbx
    mov esi, SOL_SOCKET
    mov edx, SO_REUSEADDR
    lea rcx, [rsp + 16]
    mov r8d, 4
    call setsockopt
    test rax, rax
    js .close_and_fail

    ; ---- 3: bind(fd, &sockaddr, 16) ----
    mov rdi, rbx
    lea rsi, [rsp]
    mov edx, 16
    call bind
    test rax, rax
    js .close_and_fail

    ; ---- 4: listen(fd, backlog) ----
    mov rdi, rbx
    mov esi, ebp
    call listen
    test rax, rax
    js .close_and_fail

    ; Success — return the fd.
    mov rax, rbx
    jmp .done

.close_and_fail:
    ; rax holds the -errno from the failing step. Preserve it
    ; across the close so the caller sees the true root cause.
    mov [rsp + 16], rax
    mov rdi, rbx
    call close
    mov rax, [rsp + 16]

.done:
    add rsp, 24
    pop rbp
    pop rbx
    ret
