; Multiplex on a single pipe with `poll(2)`. Poll with an
; empty pipe times out after 50 ms and returns 0; write one
; byte, poll again, and this time the fd fires `POLLIN` and
; poll returns 1. Two consecutive polls exercise both the
; timeout and the ready paths of the same call.
;
; First runnable that uses libsock's `poll`. Polling is the
; portable event-loop primitive on POSIX; every server that
; multiplexes more than one fd goes through `poll`, `select`,
; or a platform-specific replacement (`epoll` on Linux,
; `kqueue` on macOS — both outside libsock's scope).
;
; Program flow:
;
;   pipe(pipefd)
;   fds[0] = { fd = pipefd[0], events = POLLIN, revents = 0 }
;   poll(fds, 1, 50)                        → 0 (timeout, empty pipe)
;   write(pipefd[1], "x", 1)
;   poll(fds, 1, 500)                       → 1 (ready)
;   assert fds[0].revents & POLLIN
;   exit(42)
;
; struct pollfd layout (both macOS and Linux):
;   +0   fd       (i32)
;   +4   events   (i16)
;   +6   revents  (i16)
;   total 8 bytes

%ifdef MACOS
%define SYS_write   0x2000004
%define SYS_close   0x2000006
%define SYS_exit    0x2000001
%else
%define SYS_write   1
%define SYS_close   3
%define SYS_exit    60
%endif

%define POLLIN      0x0001

default rel

extern pipe                             ; libio
extern poll                             ; libsock

global _start
global _main

section .rodata
one_byte: db "x"

section .bss
pipefd: resd 2
fds:    resb 8                          ; one struct pollfd

section .text

_start:
_main:
    ; ---- pipe(pipefd) ----
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; ---- Build fds[0] ----
    mov eax, [pipefd]
    mov [fds + 0], eax                  ; fd = pipefd[0]
    mov word [fds + 4], POLLIN          ; events = POLLIN
    mov word [fds + 6], 0               ; revents = 0

    ; ---- poll(fds, 1, 50) → 0 (timeout) ----
    lea rdi, [fds]
    mov esi, 1
    mov edx, 50
    call poll
    test rax, rax
    jnz .fail                           ; expect exactly 0

    ; ---- write one byte into the pipe ----
    mov edi, [pipefd + 4]
    lea rsi, [one_byte]
    mov edx, 1
    mov rax, SYS_write
    syscall

    ; ---- poll(fds, 1, 500) → 1 (POLLIN) ----
    ; Reset revents; poll fills it on ready.
    mov word [fds + 6], 0
    lea rdi, [fds]
    mov esi, 1
    mov edx, 500
    call poll
    cmp rax, 1
    jne .fail

    ; ---- Verify revents & POLLIN ----
    movzx eax, word [fds + 6]
    test eax, POLLIN
    jz .fail

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
