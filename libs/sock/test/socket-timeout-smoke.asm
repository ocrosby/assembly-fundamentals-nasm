; socket-timeout-smoke.asm — smoke test for the v1.3 util
; helpers set_recv_timeout_ms and set_send_timeout_ms.
;
; Standalone: no Python peer. Uses socketpair(AF_UNIX,
; SOCK_STREAM) so both ends live in this process.
;
; Sub-check ids:
;
;   1  socketpair(AF_UNIX, SOCK_STREAM, 0, sv) → 0
;   2  set_recv_timeout_ms(fd_a, 100) → 0
;   3  set_send_timeout_ms(fd_a, 200) → 0
;   4  set_recv_timeout_ms(fd_a, 0)   → 0    (0 means indefinite)
;   5  set_recv_timeout_ms(BAD_FD, 100) → negative errno
;      (exercises the fail path — proves the wrappers propagate
;      the underlying setsockopt errno rather than silently
;      dropping it)
;   6  close(fd_a); close(fd_b)

%define AF_UNIX     1
%define SOCK_STREAM 1
%define BAD_FD      999999

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%define SYS_close 0x2000006
%else
%define SYS_write 1
%define SYS_exit  60
%define SYS_close 3
%endif

default rel

extern socketpair
extern set_recv_timeout_ms, set_send_timeout_ms

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
sv:       resd 2                     ; socketpair writes 2 fds here

section .text

_start:
_main:
    ; ---- 1: socketpair(AF_UNIX, SOCK_STREAM, 0, sv) → 0 ----
    mov byte [fail_id], '1'
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM
    xor edx, edx
    lea rcx, [sv]
    call socketpair
    test rax, rax
    jnz .fail
    mov r13d, [sv]                   ; fd_a
    mov r14d, [sv + 4]               ; fd_b

    ; ---- 2: set_recv_timeout_ms(fd_a, 100) → 0 ----
    mov byte [fail_id], '2'
    mov edi, r13d
    mov esi, 100
    call set_recv_timeout_ms
    test rax, rax
    jnz .fail

    ; ---- 3: set_send_timeout_ms(fd_a, 200) → 0 ----
    mov byte [fail_id], '3'
    mov edi, r13d
    mov esi, 200
    call set_send_timeout_ms
    test rax, rax
    jnz .fail

    ; ---- 4: set_recv_timeout_ms(fd_a, 0) → 0 ----
    mov byte [fail_id], '4'
    mov edi, r13d
    xor esi, esi
    call set_recv_timeout_ms
    test rax, rax
    jnz .fail

    ; ---- 5: set_recv_timeout_ms(BAD_FD, 100) → < 0 ----
    mov byte [fail_id], '5'
    mov edi, BAD_FD
    mov esi, 100
    call set_recv_timeout_ms
    test rax, rax
    jns .fail                        ; want negative

    ; ---- 6: close(fd_a); close(fd_b) ----
    mov byte [fail_id], '6'
    mov edi, r13d
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_a_ok
    neg rax
.close_a_ok:
%endif
    test rax, rax
    jnz .fail

    mov edi, r14d
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_b_ok
    neg rax
.close_b_ok:
%endif
    test rax, rax
    jnz .fail

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall
