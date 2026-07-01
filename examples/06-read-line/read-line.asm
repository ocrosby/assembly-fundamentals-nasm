; Read up to 128 bytes from standard input into a `.bss` buffer, then
; echo those bytes back to standard output. On a line-buffered TTY
; this is naturally "read a line" — `sys_read` returns as soon as the
; user hits Enter, so the newline is part of what we write back.
;
; New in this example: a `.bss` buffer sized by an `equ` constant,
; and generalizing `sys_read` from 1 byte (05) to N bytes.

%ifdef MACOS
%define SYS_READ  0x2000003
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_READ  0
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

BUF_SIZE equ 128

default rel
global _start
global _main

section .text

_start:
_main:
    mov rax, SYS_READ
    mov rdi, 0                       ; fd = stdin
    lea rsi, [buf]
    mov rdx, BUF_SIZE                ; up to 128 bytes
    syscall                          ; rax = bytes read

    test rax, rax
    jle .exit                        ; EOF or error — nothing to echo

    mov rdx, rax                     ; write exactly what we read
    mov rax, SYS_WRITE
    mov rdi, 1                       ; fd = stdout
    lea rsi, [buf]
    syscall

.exit:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

section .bss
buf: resb BUF_SIZE
