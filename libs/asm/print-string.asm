; print_string(buf: rdi, len: rsi) -> rax = bytes written
;
; Wraps sys_write(1, buf, len). The System V AMD64 ABI puts the
; first three integer arguments in rdi, rsi, rdx — the same order
; the write(2) syscall expects for (fd, buf, len) — so all this
; wrapper does is slide the caller's (buf, len) into (rsi, rdx),
; put stdout in rdi, and issue the syscall.
;
; No callee-saved registers are touched, so callers do not need to
; preserve rbx, rbp, or r12–r15 around a call to this routine.

%ifdef MACOS
%define SYS_WRITE 0x2000004         ; BSD class 2, call 4
%else
%define SYS_WRITE 1                 ; Linux write(2)
%endif

default rel

global print_string

section .text

print_string:
    mov rdx, rsi                    ; arg 3: len
    mov rsi, rdi                    ; arg 2: buf
    mov rdi, 1                      ; arg 1: fd = stdout
    mov rax, SYS_WRITE              ; syscall number
    syscall                         ; sys_write(1, buf, len)
    ret                             ; rax already holds byte count
