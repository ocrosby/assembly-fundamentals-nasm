; Write "Hello, world!" to standard output, then exit cleanly.
;
; New in this example: a second syscall (`write`), the `.rodata`
; section for read-only data, `lea` for taking a label's address,
; and the `equ $ - msg` idiom for assemble-time string length.

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
            xor     rdi, rdi
            syscall

            section .rodata
msg:        db      "Hello, world!", 10
msg_len:    equ     $ - msg
