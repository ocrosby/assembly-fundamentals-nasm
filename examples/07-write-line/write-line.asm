; Write a full line — `"Hello, world!"` plus a newline — to standard
; output, then exit cleanly. Same body as the classic hello-world
; program under a name that makes its role in the I/O series
; explicit: writing a fixed-length line is the natural counterpart
; to reading one (chapter 06).
;
; New in this example: a message in `.rodata` (not `.bss` — this
; data is read-only), `lea` for taking the message's address, and
; the assemble-time length computation `equ $ - msg`.

%ifdef MACOS
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    mov rax, SYS_WRITE
    mov rdi, 1                       ; arg 1: fd = stdout
    lea rsi, [msg]                   ; arg 2: buffer
    mov rdx, msg_len                 ; arg 3: byte count
    syscall                          ; sys_write(stdout, msg, msg_len)

    mov rax, SYS_EXIT
    xor rdi, rdi                     ; status = 0
    syscall

section .rodata
msg: db "Hello, world!", 10          ; 10 = newline (LF)
msg_len: equ $ - msg
