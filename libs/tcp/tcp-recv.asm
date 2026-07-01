; tcp_recv(fd: rdi, buf: rsi, len: rdx) -> rax = bytes read or negative errno
;
; Wraps read(fd, buf, len). rax == 0 means the peer closed the
; connection cleanly (EOF). Short reads are normal for TCP —
; callers loop until they have what they need, or hit rax == 0,
; or hit a negative errno.
;
; read(2) works on connected TCP sockets on both Linux and macOS;
; recvfrom is not required for this path.

%ifdef MACOS
%define SYS_READ 0x2000003
%else
%define SYS_READ 0
%endif

default rel

global tcp_recv

section .text

tcp_recv:
    mov rax, SYS_READ               ; syscall number
    syscall                         ; read(fd, buf, len)
%ifdef MACOS
    jnc .ok
    neg rax
.ok:
%endif
    ret
