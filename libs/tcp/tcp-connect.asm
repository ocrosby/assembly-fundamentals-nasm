; tcp_connect(ip: rdi, port: rsi) -> rax = fd or negative errno
;
; Creates an AF_INET / SOCK_STREAM socket and connects it to
; (ip, port). The ip argument is a u32 already in network byte
; order (e.g. 0x0100007F for 127.0.0.1). The port argument is a
; plain host-order u16; the byte-swap to network order is done
; internally.
;
; On success returns the connected socket fd. On socket() failure
; returns the negative errno directly. On connect() failure the
; socket is closed before returning the negative errno, so the
; caller never has to clean up a half-open fd.

%ifdef MACOS
%define SYS_SOCKET  0x2000061       ; BSD class 2, call 97
%define SYS_CONNECT 0x2000062       ; BSD class 2, call 98
%define SYS_CLOSE   0x2000006
%define SIN_HEADER  0x0210          ; sin_len=16, sin_family=AF_INET=2
%else
%define SYS_SOCKET  41
%define SYS_CONNECT 42
%define SYS_CLOSE   3
%define SIN_HEADER  0x0002          ; sin_family=AF_INET=2 (u16 little-endian)
%endif

%define AF_INET     2
%define SOCK_STREAM 1

%macro SYSCALL_NORM 0
    syscall
%ifdef MACOS
    jnc %%ok
    neg rax
%%ok:
%endif
%endmacro

default rel

global tcp_connect

section .text

tcp_connect:
    push rbx                        ; callee-saved: fd across syscalls
    push r12                        ; callee-saved: ip
    push r13                        ; callee-saved: port
                                    ; rsp is 16-byte aligned here

    mov r12, rdi                    ; save ip (network order)
    mov r13, rsi                    ; save port (host order)

    ; socket(AF_INET, SOCK_STREAM, 0)
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    xor edx, edx                    ; protocol = 0
    mov rax, SYS_SOCKET
    SYSCALL_NORM
    test rax, rax
    js .done                        ; socket failed: return -errno as-is
    mov rbx, rax                    ; save fd

    ; Build sockaddr_in on the stack (16 bytes).
    sub rsp, 16
    mov word [rsp + 0], SIN_HEADER  ; sin_family (+ sin_len on macOS)
    mov ax, r13w                    ; port, host order
    rol ax, 8                       ; htons: 16-bit byte swap
    mov [rsp + 2], ax               ; sin_port
    mov [rsp + 4], r12d             ; sin_addr, already network order
    mov qword [rsp + 8], 0          ; sin_zero

    ; connect(fd, sockaddr, 16)
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 16                     ; socklen_t
    mov rax, SYS_CONNECT
    SYSCALL_NORM
    add rsp, 16                     ; discard sockaddr
    test rax, rax
    js .connect_failed
    mov rax, rbx                    ; success: return fd
    jmp .done

.connect_failed:
    ; rax has the negative errno; rbx has the fd. Close the fd
    ; but preserve the original error across the close syscall.
    mov r12, rax                    ; save error (r12 is free after ip)
    mov rdi, rbx
    mov rax, SYS_CLOSE
    SYSCALL_NORM                    ; ignore close() result
    mov rax, r12                    ; restore error

.done:
    pop r13
    pop r12
    pop rbx
    ret
