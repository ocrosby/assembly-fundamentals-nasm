; Read a single byte from standard input and echo it back to standard
; output. With no input piped in, `sys_read` returns 0 (EOF) and the
; program exits cleanly without writing anything.
;
; New in this example: the `sys_read` syscall, the `.bss` section for
; an uninitialized single-byte buffer, and reading the syscall's
; return value (bytes-actually-read) out of `rax`.

%ifdef MACOS
%define SYS_READ  0x2000003
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_READ  0
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    mov rax, SYS_READ
    mov rdi, 0                       ; arg 1: fd = stdin
    lea rsi, [buf]                   ; arg 2: destination buffer
    mov rdx, 1                       ; arg 3: max bytes to read
    syscall                          ; rax = bytes read (0 = EOF, <0 = error)

    test rax, rax
    jle .exit                        ; nothing read — skip the echo

    mov rdx, rax                     ; length to write = length read
    mov rax, SYS_WRITE
    mov rdi, 1                       ; fd = stdout
    lea rsi, [buf]
    syscall

.exit:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

section .bss
buf: resb 1
