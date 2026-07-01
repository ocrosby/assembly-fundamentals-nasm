; tcp_close(fd: rdi) -> rax = 0 or negative errno
;
; Wraps close(fd). On macOS the BSD carry-flag errno convention is
; normalized to the Linux negative-errno convention, so callers see
; the same "non-negative on success, negative on failure" shape on
; both platforms.

%ifdef MACOS
%define SYS_CLOSE 0x2000006
%else
%define SYS_CLOSE 3
%endif

default rel

global tcp_close

section .text

tcp_close:
    mov rax, SYS_CLOSE              ; syscall number
    syscall                         ; close(fd)
%ifdef MACOS
    jnc .ok                         ; CF=0 → success, rax already 0
    neg rax                         ; CF=1 → convert positive errno to negative
.ok:
%endif
    ret
