; Minimal `cp`: open a source path for reading and a destination
; path for writing, then loop `read` → `write` in 4 KiB chunks
; until the source EOFs, close both descriptors, and exit.
;
; Requires `/tmp/nasm-copy-src.txt` to exist. The example's
; Makefile `run` target seeds one with test content and reports the
; produced `/tmp/nasm-copy-dst.txt`.
;
; New in this example: managing two open file descriptors in
; parallel (source in `r12`, destination in `r13`, both callee-
; saved so they survive across `syscall`s), and combining the
; open/read/close pattern from 09-read-file with the
; open-for-write pattern from 10-write-file.

%ifdef MACOS
%define SYS_OPEN  0x2000005
%define SYS_CLOSE 0x2000006
%define SYS_READ  0x2000003
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%define O_RDONLY  0x0000
%define O_WRONLY  0x0001
%define O_CREAT   0x0200
%define O_TRUNC   0x0400
%else
%define SYS_OPEN  2
%define SYS_CLOSE 3
%define SYS_READ  0
%define SYS_WRITE 1
%define SYS_EXIT  60
%define O_RDONLY  0x0000
%define O_WRONLY  0x0001
%define O_CREAT   0x0040
%define O_TRUNC   0x0200
%endif

BUF_SIZE equ 4096

default rel
global _start
global _main

section .text

_start:
_main:
    ; src_fd = open(src, O_RDONLY)
    mov rax, SYS_OPEN
    lea rdi, [src]
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall
    test rax, rax
    js .fail
    mov r12, rax                     ; r12 = src_fd

    ; dst_fd = open(dst, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov rax, SYS_OPEN
    lea rdi, [dst]
    mov rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov rdx, 420                     ; 0o644 — rw-r--r--
    syscall
    test rax, rax
    js .fail_close_src
    mov r13, rax                     ; r13 = dst_fd

.copy_loop:
    ; n = read(src_fd, buf, BUF_SIZE)
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, BUF_SIZE
    syscall
    test rax, rax
    jz .done                         ; source EOF
    js .fail_close_both

    ; write(dst_fd, buf, n)
    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, r13
    lea rsi, [buf]
    syscall
    test rax, rax
    js .fail_close_both
    jmp .copy_loop

.done:
    mov rax, SYS_CLOSE
    mov rdi, r13
    syscall
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

.fail_close_both:
    mov rax, SYS_CLOSE
    mov rdi, r13
    syscall
.fail_close_src:
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall
.fail:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

section .rodata
src: db "/tmp/nasm-copy-src.txt", 0
dst: db "/tmp/nasm-copy-dst.txt", 0

section .bss
buf: resb BUF_SIZE
