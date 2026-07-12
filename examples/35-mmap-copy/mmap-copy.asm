; Copy a small file into a fresh destination file using two
; mmap regions instead of a read/write loop. Exit 42 on
; success (the byte value copied through the mappings verifies
; the whole pipeline ran); exit 1 on any syscall error.
;
; Builds on 31-mmap-file (file-backed PROT_READ MAP_PRIVATE)
; and 32-mmap-shared (PROT_READ|PROT_WRITE MAP_SHARED). The
; new idea is holding *two* mappings live at once and moving
; bytes between them in userspace. That is the stripped-down
; form of the "memory-mapped I/O beats read/write for small
; regions" pattern — the kernel sees no read/write syscalls
; for the copy itself, only the mmaps and the eventual munmap.
;
; Program flow:
;
;   open(src_path, O_RDWR|O_CREAT|O_TRUNC, 0600)   → src_fd
;   ftruncate(src_fd, MSG_LEN)                     → seed backing pages
;   pwrite(src_fd, msg, MSG_LEN, 0)                → "HELLO WORLD!"
;   src = mmap(NULL, MSG_LEN, PROT_READ, MAP_PRIVATE, src_fd, 0)
;
;   open(dst_path, O_RDWR|O_CREAT|O_TRUNC, 0600)   → dst_fd
;   ftruncate(dst_fd, MSG_LEN)                     → 12 zero bytes
;   dst = mmap(NULL, MSG_LEN, PROT_READ|PROT_WRITE, MAP_SHARED,
;              dst_fd, 0)
;
;   for i in 0..MSG_LEN-1:                          ; inline byte copy
;       dst[i] = src[i]
;
;   verify_byte = dst[0]                            ; should be 'H'
;
;   munmap(src, MSG_LEN); munmap(dst, MSG_LEN)
;   exit(42)                                        ; sentinel — not the byte
;
; The exit code is 42 rather than the copied byte because 'H'
; is 0x48 = 72, which is a valid exit status but a less
; recognizable sentinel than the 42 the rest of the mmap
; examples in this repo use. Sub-checking `dst[0] == 'H'`
; before exiting keeps the assertion that the copy actually
; landed the right byte, without breaking the family
; convention.

%ifdef MACOS
%define SYS_exit    0x2000001
%define O_CREAT     0x0200
%define O_TRUNC     0x0400
%else
%define SYS_exit    60
%define O_CREAT     0x40
%define O_TRUNC     0x200
%endif

%define O_RDWR       2
%define PROT_READ    1
%define PROT_WRITE   2
%define MAP_PRIVATE  2
%define MAP_SHARED   1
%define MSG_LEN      12
%define EXIT_OK      42
%define EXPECTED_H   'H'

default rel

extern open, ftruncate, pwrite, mmap, munmap

global _start
global _main

section .rodata
src_path: db "/tmp/nasm-mmap-copy.src", 0
dst_path: db "/tmp/nasm-mmap-copy.dst", 0
msg:      db "HELLO WORLD!"           ; 12 bytes, matches MSG_LEN

section .text

_start:
_main:
    ; ---- open source, size it, seed it ----
    lea rdi, [src_path]
    mov esi, O_RDWR | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov r12d, eax                     ; src_fd (callee-saved)

    mov edi, r12d
    mov rsi, MSG_LEN
    call ftruncate
    test rax, rax
    jnz .fail

    mov edi, r12d
    lea rsi, [msg]
    mov edx, MSG_LEN
    xor ecx, ecx                      ; offset = 0
    call pwrite
    cmp rax, MSG_LEN
    jne .fail

    ; ---- mmap source: PROT_READ, MAP_PRIVATE ----
    ; Read-only view of the source file is enough — the copy
    ; only ever reads from this mapping.
    xor edi, edi                      ; addr = NULL
    mov esi, MSG_LEN
    mov edx, PROT_READ
    mov ecx, MAP_PRIVATE
    mov r8d, r12d                     ; fd
    xor r9d, r9d                      ; offset = 0
    call mmap
    test rax, rax
    js .fail
    mov rbx, rax                      ; src mapping (callee-saved)

    ; ---- open destination, size it (zero-filled) ----
    ; ftruncate on a fresh file writes MSG_LEN zero bytes,
    ; which is what the destination mapping starts from. The
    ; inline copy loop below overwrites them with the source
    ; contents.
    lea rdi, [dst_path]
    mov esi, O_RDWR | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov r13d, eax                     ; dst_fd (callee-saved)

    mov edi, r13d
    mov rsi, MSG_LEN
    call ftruncate
    test rax, rax
    jnz .fail

    ; ---- mmap destination: PROT_READ|PROT_WRITE, MAP_SHARED ----
    ; MAP_SHARED so the writes made through the mapping reach
    ; the underlying file on flush/unmap. MAP_PRIVATE here
    ; would keep the writes in this process's page cache and
    ; the file on disk would stay all zeros.
    xor edi, edi
    mov esi, MSG_LEN
    mov edx, PROT_READ | PROT_WRITE
    mov ecx, MAP_SHARED
    mov r8d, r13d
    xor r9d, r9d
    call mmap
    test rax, rax
    js .fail
    mov r14, rax                      ; dst mapping (callee-saved)

    ; ---- inline byte copy: dst[i] = src[i] for i in [0, MSG_LEN) ----
    ; Deliberately spelled out. libstr's memcpy would fit here
    ; too, but the point of the example is that the copy is
    ; happening entirely in userspace — no read/write syscall
    ; against either fd. The kernel only sees the mmaps and
    ; the eventual munmap.
    xor ecx, ecx                      ; index i
.copy_loop:
    mov al, [rbx + rcx]               ; src[i]
    mov [r14 + rcx], al               ; dst[i] = src[i]
    inc rcx
    cmp rcx, MSG_LEN
    jb .copy_loop

    ; ---- Verify dst[0] == 'H' ----
    ; End-to-end assertion that the copy actually landed the
    ; right byte at the destination mapping. Any misconfigured
    ; mmap flag combination that yields zero-fill or SIGBUS
    ; instead of the real bytes falls out as a wrong exit code.
    cmp byte [r14], EXPECTED_H
    jne .fail

    ; ---- munmap both regions ----
    mov rdi, rbx
    mov esi, MSG_LEN
    call munmap
    test rax, rax
    jnz .fail

    mov rdi, r14
    mov esi, MSG_LEN
    call munmap
    test rax, rax
    jnz .fail

    ; ---- exit(42) ----
    mov rax, SYS_exit
    mov edi, EXIT_OK
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
