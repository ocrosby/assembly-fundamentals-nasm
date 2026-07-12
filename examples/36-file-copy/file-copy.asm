; Copy a small file into a fresh destination via libio's
; `file_copy` composed helper. Exit 42 on success; exit 1 on
; any syscall error.
;
; This example is the "look how short it becomes when the
; library owns the pattern" companion to
; [35-mmap-copy](../35-mmap-copy/). That example spelled the
; open + ftruncate + double-mmap + rep-movsb + munmap sequence
; out inline so the reader could see every syscall in play.
; This example calls one entry point instead:
;
;   file_copy(src_path, dst_path) → 0 or -errno
;
; libio hides the two-mmap dance, the zero-length short-circuit,
; and the layered error cleanup. What is left in the caller is
; the seeding step (write "HELLO WORLD!" to the source with a
; raw sys_write, since libio does not export write) and the
; file_copy call itself.
;
; Program flow:
;
;   open(src, O_WRONLY|O_CREAT|O_TRUNC, 0600) → src_fd
;   write(src_fd, "HELLO WORLD!", 12)         → seed source
;   close(src_fd)
;   file_copy(src_path, dst_path)             → 0 on success
;   exit(42)

%ifdef MACOS
%define SYS_write   0x2000004
%define SYS_close   0x2000006
%define SYS_exit    0x2000001
%define O_CREAT     0x0200
%define O_TRUNC     0x0400
%else
%define SYS_write   1
%define SYS_close   3
%define SYS_exit    60
%define O_CREAT     0x40
%define O_TRUNC     0x200
%endif

%define O_WRONLY     1

default rel

extern open, file_copy

global _start
global _main

section .rodata
src_path: db "/tmp/nasm-file-copy.src", 0
dst_path: db "/tmp/nasm-file-copy.dst", 0
msg:      db "HELLO WORLD!"
msg_len:  equ $ - msg               ; 12

section .text

_start:
_main:
    ; ---- Seed the source with "HELLO WORLD!" ----
    ; libio does not export `write` (that lives in libsock,
    ; per the two-archive rule), so this half of the fixture
    ; uses raw sys_write to avoid pulling libsock in for one
    ; call. libio's `open` still handles the file creation.
    lea rdi, [src_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov ebx, eax                    ; src_fd (callee-saved)

    mov edi, ebx
    lea rsi, [msg]
    mov edx, msg_len
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .write_ok
    neg rax
.write_ok:
%endif
    cmp rax, msg_len
    jne .fail

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; ---- file_copy(src_path, dst_path) ----
    ; Everything the composed helper does is documented in
    ; libs/io/util/file-copy.asm — from the caller's point of
    ; view it is a single call that returns 0 on success or
    ; a negative errno.
    lea rdi, [src_path]
    lea rsi, [dst_path]
    call file_copy
    test rax, rax
    jnz .fail

    ; ---- exit(42) ----
    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
