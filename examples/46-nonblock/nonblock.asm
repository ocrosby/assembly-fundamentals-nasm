; Toggle O_NONBLOCK on a pipe's read end via fcntl, then
; attempt a read on an empty pipe. The read returns -EAGAIN
; (or -EWOULDBLOCK — same numeric value on both platforms)
; instead of blocking forever. Exits 42 on that observation.
;
; First runnable that uses libio's `fcntl`. Non-blocking fds
; are the underlying mechanic of every event loop, every
; async runtime, and every real-shape server that handles
; more than one connection at a time.
;
; Program flow:
;
;   pipe(pipefd)
;   old_flags = fcntl(pipefd[0], F_GETFL, 0)
;   fcntl(pipefd[0], F_SETFL, old_flags | O_NONBLOCK) → 0
;   read(pipefd[0], buf, 1) → -EAGAIN                (empty; would-block)
;   close(pipefd[0..1])
;   exit(42)

%include "syscall.inc"

%ifdef MACOS
%define SYS_read  0x2000003
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%define EAGAIN    35
%else
%define SYS_read  0
%define SYS_close 3
%define SYS_exit  60
%define EAGAIN    11
%endif

default rel

extern pipe, fcntl

global _start
global _main

section .bss
pipefd:  resd 2
buf:     resb 4

section .text

_start:
_main:
    ; ---- pipe(pipefd) ----
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; ---- Read current flags ----
    mov edi, [pipefd]
    mov esi, F_GETFL
    xor edx, edx
    call fcntl
    test rax, rax
    js .fail
    mov r12d, eax                    ; save old flags

    ; ---- Set O_NONBLOCK ----
    mov edi, [pipefd]
    mov esi, F_SETFL
    mov edx, r12d
    or edx, O_NONBLOCK
    call fcntl
    test rax, rax
    jnz .fail

    ; ---- Attempt read on empty pipe → -EAGAIN ----
    ; Raw sys_read since libio does not export read.
    mov edi, [pipefd]
    lea rsi, [buf]
    mov edx, 1
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .read_ok
    neg rax
.read_ok:
%endif
    ; EAGAIN differs per platform (35 macOS, 11 Linux).
    ; The wrapper's SYSCALL_NORM normalizes to -EAGAIN
    ; either way.
    cmp rax, -EAGAIN
    jne .fail

    ; ---- Close both ends and exit(42) ----
    mov edi, [pipefd]
    mov rax, SYS_close
    syscall
    mov edi, [pipefd + 4]
    mov rax, SYS_close
    syscall

    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
