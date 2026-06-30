; Hello, world — writes a string to stdout via the write syscall and exits.
; See docs/02-hello-world.md for the walk-through.

%ifdef MACOS
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

            default rel
            global  _start
            global  _main

            section .text
_start:
_main:      mov     rax, SYS_WRITE
            mov     rdi, 1                  ; fd = stdout
            lea     rsi, [msg]
            mov     rdx, msg_len
            syscall

            mov     rax, SYS_EXIT
            xor     rdi, rdi                ; status = 0
            syscall

            section .rodata
msg:        db      "Hello, world!", 10
msg_len:    equ     $ - msg
