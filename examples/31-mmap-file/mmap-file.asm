; Create a scratch file, size it to one page, drop a
; distinctive byte at offset 0, then read that byte back
; through a file-backed mmap and exit with its value. Exit 42
; on success (the byte we planted); exit 1 on any syscall
; error.
;
; Introduces the second useful `mmap` flag combination on top
; of [30-shared-mapping](../30-shared-mapping/): drop
; `MAP_ANON`, pass a real fd and offset. The kernel now backs
; the mapping with the file's contents, so reads from the
; mapped range return the file's bytes and writes (were we
; using `PROT_WRITE`) would eventually reach disk on
; `msync` or unmap.
;
; File shape by design:
;
;   * ftruncate to PAGE_SIZE first — the mapping length must
;     not exceed the file's size on Linux (a read past EOF
;     raises SIGBUS). macOS zero-fills the tail instead, but
;     depending on that would make the example
;     platform-brittle.
;   * pwrite one byte at offset 0. The remaining 4095 bytes
;     stay as zero-fill from ftruncate.
;
; The exit-code trick — return the byte we read back via the
; mapping — makes CI's expected-exit assertion double as a
; proof that the whole cycle ran: any wrong byte or SIGSEGV
; produces a different exit.

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
%define MAP_PRIVATE  2
%define PAGE_SIZE    4096

default rel

extern open, ftruncate, pwrite, mmap, munmap

global _start
global _main

section .rodata
path:   db "/tmp/nasm-mmap-file.dat", 0
byte42: db 42

section .text

_start:
_main:
    ; ---- open(path, O_RDWR|O_CREAT|O_TRUNC, 0600) ----
    lea rdi, [path]
    mov esi, O_RDWR | O_CREAT | O_TRUNC
    mov edx, 0600q                  ; permission bits (owner rw)
    call open
    test rax, rax
    js .fail
    mov r12d, eax                   ; fd (callee-saved)

    ; ---- ftruncate(fd, PAGE_SIZE) ----
    ; Grow the empty file to a full page so the mmap below
    ; stays within the file's addressable extent on every
    ; platform. ftruncate zero-fills the new bytes.
    mov edi, r12d
    mov rsi, PAGE_SIZE
    call ftruncate
    test rax, rax
    jnz .fail

    ; ---- pwrite(fd, &byte42, 1, 0) ----
    ; Overwrite the first byte with 42. positioned-write does
    ; not touch the fd's seek offset — useful here even though
    ; we only have one write to perform.
    mov edi, r12d
    lea rsi, [byte42]
    mov edx, 1
    xor ecx, ecx                    ; offset = 0
    call pwrite
    cmp rax, 1
    jne .fail

    ; ---- mmap(NULL, PAGE_SIZE, PROT_READ, MAP_PRIVATE, fd, 0) ----
    ; No MAP_ANON — the kernel goes through the fd's inode and
    ; maps the file's contents. PROT_READ + MAP_PRIVATE gives
    ; a copy-on-write read-only view; writes we made through
    ; the mapping would be private to this process.
    xor edi, edi                    ; addr = NULL
    mov esi, PAGE_SIZE
    mov edx, PROT_READ
    mov ecx, MAP_PRIVATE
    mov r8d, r12d                   ; fd
    xor r9d, r9d                    ; offset = 0
    call mmap
    test rax, rax
    js .fail
    mov rbx, rax                    ; mapping address (callee-saved)

    ; ---- Read byte[0] via the mapping ----
    ; If the file-backed page had not been genuinely mapped,
    ; this dereference would SIGSEGV — same failure mode as
    ; example 30 but through a file rather than anonymous
    ; memory.
    movzx r13d, byte [rbx]

    ; ---- munmap(addr, PAGE_SIZE) ----
    mov rdi, rbx
    mov esi, PAGE_SIZE
    call munmap
    test rax, rax
    jnz .fail

    ; ---- exit(byte we read back) — should be 42 ----
    mov rax, SYS_exit
    mov edi, r13d
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
