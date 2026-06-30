; Write "Hello, world!" to standard output, then exit cleanly.
;
; New in this example: a second syscall (`write`), the `.rodata`
; section for read-only data, `lea` for taking a label's address,
; and the `equ $ - msg` idiom for an assemble-time string length.

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
    mov rax, SYS_WRITE              ; syscall number for sys_write
    mov rdi, 1                      ; arg 1: file descriptor = stdout
    lea rsi, [msg]                  ; arg 2: pointer to the buffer
    mov rdx, msg_len                ; arg 3: byte count
    syscall                         ; sys_write(stdout, msg, msg_len)

    mov rax, SYS_EXIT               ; syscall number for sys_exit
    xor rdi, rdi                    ; arg 1: status = 0
    syscall                         ; sys_exit(0)

section .rodata
msg: db "Hello, world!", 10         ; 10 = newline (LF)
msg_len: equ $ - msg                ; $ is the current address; computed at assemble time
