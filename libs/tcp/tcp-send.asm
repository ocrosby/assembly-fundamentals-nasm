; tcp_send(fd: rdi, buf: rsi, len: rdx) -> rax = bytes written or negative errno
;
; Wraps write(fd, buf, len). One syscall, whatever the kernel
; accepted — partial writes are the caller's problem. On macOS the
; BSD carry-flag errno convention is normalized to Linux's
; negative-errno convention.
;
; write(2) works on connected TCP sockets on both Linux and macOS;
; a dedicated sendto/send syscall is not required for this path.

%ifdef MACOS
%define SYS_WRITE 0x2000004
%else
%define SYS_WRITE 1
%endif

default rel

global tcp_send

section .text

tcp_send:
    mov rax, SYS_WRITE              ; syscall number
    syscall                         ; write(fd, buf, len)
%ifdef MACOS
    jnc .ok
    neg rax
.ok:
%endif
    ret
