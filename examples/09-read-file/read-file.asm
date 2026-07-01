; A minimal `cat`: open a hardcoded path with `O_RDONLY`, read the
; contents in 4 KiB chunks, write each chunk to stdout, close the
; file descriptor, and exit.
;
; Requires the input file to exist at `/tmp/nasm-read-file.txt`.
; The example's Makefile `run` target seeds one with test content.
;
; New in this example: the `sys_open` and `sys_close` syscalls,
; saving the returned file descriptor in a callee-saved register
; (`r12`) so it survives across intermediate syscalls, and the
; two-branch error handling (`js .fail`) — a negative return value
; from `sys_open` or `sys_read` is `-errno`.

%ifdef MACOS
%define SYS_OPEN  0x2000005
%define SYS_CLOSE 0x2000006
%define SYS_READ  0x2000003
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_OPEN  2
%define SYS_CLOSE 3
%define SYS_READ  0
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

O_RDONLY equ 0
BUF_SIZE equ 4096

default rel
global _start
global _main

section .text

_start:
_main:
    ; fd = open(path, O_RDONLY)
    mov rax, SYS_OPEN
    lea rdi, [path]
    mov rsi, O_RDONLY
    xor rdx, rdx                     ; mode ignored without O_CREAT
    syscall
    test rax, rax
    js .fail                         ; negative → open error
    mov r12, rax                     ; r12 = fd

.read_loop:
    ; n = read(fd, buf, BUF_SIZE)
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, BUF_SIZE
    syscall
    test rax, rax
    jz .done                         ; EOF
    js .fail                         ; read error

    ; write(1, buf, n)
    mov rdx, rax                     ; length = bytes read
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [buf]
    syscall
    jmp .read_loop

.done:
    ; close(fd)
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi                     ; status = 0
    syscall

.fail:
    mov rax, SYS_EXIT
    mov rdi, 1                       ; status = 1 (open or read failed)
    syscall

section .rodata
path: db "/tmp/nasm-read-file.txt", 0

section .bss
buf: resb BUF_SIZE
