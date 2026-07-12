; mmap-smoke.asm — v1.9 mmap + munmap coverage.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; prints "FAIL:<id>\n" to stderr and exits 1 otherwise.
;
; Sub-check ids:
;
;   1  mmap(NULL, 4096, PROT_R|PROT_W, MAP_ANON|MAP_PRIVATE, -1, 0)
;      → non-negative address (positive kernel page pointer)
;   2  write 0x42 to [addr] + read back to verify the mapping
;      is actually writable and readable
;   3  munmap(addr, 4096) → 0
;   4  mmap(NULL, PAGE_SIZE, PROT_R, MAP_PRIVATE, fd=999999, 0)
;      → negative (-EBADF). A non-anonymous mapping goes
;      through the kernel's fd table; a bogus fd forces the
;      failure branch of SYSCALL_NORM to fire.
;
; Note: macOS's raw SYS_mmap accepts length=0 and returns 0
; with CF=0 (libc adds the "length is 0 → EINVAL" check in
; userspace before the syscall). The raw kernel is happy to
; make a zero-page mapping, so we test the error path via a
; bad fd instead.

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

%define PAGE_SIZE 4096

default rel

extern mmap, munmap
extern panic                        ; libasm v1.1

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
saved_addr: resq 1

section .text

_start:
_main:
    ; ---- 1: mmap anonymous RW page ----
    mov byte [fail_id], '1'
    xor edi, edi                    ; addr = NULL (kernel picks)
    mov esi, PAGE_SIZE
    mov edx, PROT_READ | PROT_WRITE
    mov ecx, MAP_ANON | MAP_PRIVATE
    mov r8d, -1                     ; fd = -1 (anonymous)
    xor r9d, r9d                    ; offset = 0
    call mmap
    test rax, rax
    js .fail                        ; negative = -errno
    mov [saved_addr], rax

    ; ---- 2: write + read-back round trip ----
    mov byte [fail_id], '2'
    mov rax, [saved_addr]
    mov byte [rax], 0x42
    cmp byte [rax], 0x42
    jne .fail

    ; ---- 3: munmap → 0 ----
    mov byte [fail_id], '3'
    mov rdi, [saved_addr]
    mov esi, PAGE_SIZE
    call munmap
    test rax, rax
    jnz .fail

    ; ---- 4: mmap with a bad fd (non-anon) → -EBADF ----
    ; macOS's raw kernel accepts length=0 (unlike libc which
    ; adds a userspace EINVAL check), so we force the error
    ; branch by dropping MAP_ANON and passing an fd that
    ; cannot possibly be open (999999).
    mov byte [fail_id], '4'
    xor edi, edi
    mov esi, PAGE_SIZE
    mov edx, PROT_READ
    mov ecx, MAP_PRIVATE            ; no MAP_ANON — kernel goes to fd table
    mov r8d, 999999                 ; bogus fd
    xor r9d, r9d
    call mmap
    test rax, rax
    jns .fail                       ; want strictly negative

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    ; libasm v1.1's panic writes to stderr and exits(1). The
    ; fail_id byte was already patched in place by the check
    ; that failed, so fail_msg still starts with "FAIL:<id>".
    lea rdi, [fail_msg]
    mov esi, fail_len
    call panic
    ; unreachable — panic does not return
