; client_connect(ip_net, port_host) -> rax = client_fd or -errno
;
; The outbound counterpart to server_bind_listen. Composes the
; two syscalls every TCP client always makes into a single call:
;
;     fd = socket(AF_INET, SOCK_STREAM, 0)
;     connect(fd, sockaddr_in{ip, port}, 16)
;
; Argument shape:
;   rdi = ip_net    — u32 IPv4 in network byte order. Same
;                     convention as server_bind_listen, resolv_a,
;                     etc. — pass an inet_pton4 output for any
;                     literal, or 0x0100007F for 127.0.0.1 on
;                     little-endian x86_64.
;   rsi = port_host — u16 port in host byte order.
;
; Returns:
;   rax >= 0        — the connected client_fd, ready for
;                     read/write.
;   rax < 0         — an errno. On a connect failure the fd is
;                     closed before the errno propagates so the
;                     caller never leaks a descriptor.
;
; Behavior notes:
;   * connect() blocks until the TCP three-way handshake
;     completes, the peer refuses the connection with RST
;     (-ECONNREFUSED), or the kernel's connect timeout fires
;     (-ETIMEDOUT). This helper does NOT set a SO_SNDTIMEO
;     or make the socket non-blocking — that is the caller's
;     job when a bounded connect is required.
;   * No SO_REUSEADDR / SO_KEEPALIVE / TCP_NODELAY is set.
;     Callers that want those set them via setsockopt after
;     the fd is returned.
;
; Stack layout (24 bytes, 16-aligned before every nested call):
;   [rsp+0..15]   sockaddr_in
;   [rsp+16..23]  errno save slot (used only on close-and-fail)
;
; Register roles:
;   rbx  = client_fd — survives the connect + close calls.

%include "syscall.inc"

default rel

extern socket, connect, close

global client_connect

section .text

client_connect:
    push rbx
    sub rsp, 24

    ; Build sockaddr_in at [rsp+0..15]. Same layout used by
    ; server_bind_listen — see that file for the SIN_HEADER
    ; explanation.
    mov word [rsp + 0], SIN_HEADER
    mov ax, si                      ; port_host (low 16 of rsi)
    rol ax, 8                       ; host → network
    mov [rsp + 2], ax
    mov [rsp + 4], edi              ; ip_net (already net-order)
    mov qword [rsp + 8], 0          ; sin_zero

    ; ---- 1: socket(AF_INET, SOCK_STREAM, 0) ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .done                        ; -errno passes through
    mov rbx, rax                    ; client_fd

    ; ---- 2: connect(fd, &sockaddr, 16) ----
    mov rdi, rbx
    lea rsi, [rsp]
    mov edx, 16
    call connect
    test rax, rax
    js .close_and_fail

    ; Success — return the fd.
    mov rax, rbx
    jmp .done

.close_and_fail:
    ; rax holds the -errno from connect. Preserve it across
    ; the close so the caller sees the true root cause.
    mov [rsp + 16], rax
    mov rdi, rbx
    call close
    mov rax, [rsp + 16]

.done:
    add rsp, 24
    pop rbx
    ret
