; Read from standard input in 128-byte chunks and echo each chunk
; back to standard output, until the read syscall returns 0 (EOF).
; This is a minimal `cat` for stdin.
;
; New in this example: driving `sys_read` in a loop, and detecting
; EOF by testing whether `rax` (bytes read) came back as zero.

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
.loop:
    mov rax, SYS_READ
    mov rdi, 0                       ; fd = stdin
    lea rsi, [buf]
    mov rdx, BUF_SIZE
    syscall                          ; rax = bytes read

    test rax, rax
    jz .done                         ; rax == 0 → EOF, done
    js .done                         ; rax  < 0 → error, bail

    mov rdx, rax                     ; write exactly what we read
    mov rax, SYS_WRITE
    mov rdi, 1                       ; fd = stdout
    lea rsi, [buf]
    syscall
    jmp .loop

.done:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

section .bss
buf: resb BUF_SIZE
