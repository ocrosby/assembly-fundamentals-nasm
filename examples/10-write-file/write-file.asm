; Open (or create + truncate) a hardcoded path with mode 0644, write
; a fixed message to it, close the file, and exit. The resulting
; file appears at `/tmp/nasm-write-file.txt`.
;
; New in this example: the `O_WRONLY | O_CREAT | O_TRUNC` flag
; combination for "create or truncate for writing", the mode
; argument in `rdx` for the file's permission bits, and the
; per-platform `O_*` bitmask values (macOS and Linux use different
; numbers for `O_CREAT` and `O_TRUNC`).

%ifdef MACOS
%define SYS_OPEN  0x2000005
%define SYS_CLOSE 0x2000006
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%define O_WRONLY  0x0001
%define O_CREAT   0x0200
%define O_TRUNC   0x0400
%else
%define SYS_OPEN  2
%define SYS_CLOSE 3
%define SYS_WRITE 1
%define SYS_EXIT  60
%define O_WRONLY  0x0001
%define O_CREAT   0x0040
%define O_TRUNC   0x0200
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    ; fd = open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov rax, SYS_OPEN
    lea rdi, [path]
    mov rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov rdx, 420                     ; 0o644 in decimal — rw-r--r--
    syscall
    test rax, rax
    js .fail
    mov r12, rax                     ; r12 = fd

    ; write(fd, msg, msg_len)
    mov rax, SYS_WRITE
    mov rdi, r12
    lea rsi, [msg]
    mov rdx, msg_len
    syscall
    test rax, rax
    js .fail

    ; close(fd)
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

.fail:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

section .rodata
path: db "/tmp/nasm-write-file.txt", 0
msg:  db "written by nasm", 10
msg_len equ $ - msg
