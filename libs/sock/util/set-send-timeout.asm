; set_send_timeout_ms(fd, ms) -> rax = 0 or -errno
;
; Send-side counterpart to set_recv_timeout_ms. Bounds a socket's
; blocking send/write to *ms* milliseconds. When the timeout
; fires the send returns -EAGAIN, which typically means the
; peer's receive window is stuck full — the caller retries,
; drops the buffer, or tears down the connection.
;
; Argument shape:
;   rdi = fd
;   rsi = ms (u32)
;
; Same "ms == 0 → indefinite" convention as set_recv_timeout_ms,
; same struct-timeval-conversion math, same stack layout — this
; helper is deliberately a symmetric twin. Only the SO_* option
; differs.
;
; See set-recv-timeout.asm for the full commentary on the
; ms → timeval conversion and the cross-platform sizeof(struct
; timeval) argument.

%include "syscall.inc"

default rel

extern setsockopt

global set_send_timeout_ms

section .text

set_send_timeout_ms:
    sub rsp, 24

    mov rax, rsi
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov [rsp + 0], rax              ; tv_sec
    imul rdx, 1000
    mov [rsp + 8], rdx              ; tv_usec

    mov esi, SOL_SOCKET
    mov edx, SO_SNDTIMEO
    lea rcx, [rsp]
    mov r8d, 16
    call setsockopt

    add rsp, 24
    ret
