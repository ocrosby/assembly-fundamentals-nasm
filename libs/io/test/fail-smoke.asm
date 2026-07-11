; fail-smoke.asm — exercise the failure branch of every libio
; syscall wrapper.
;
; The success-only path in io-smoke never runs the `neg rax`
; line inside SYSCALL_NORM on macOS. This file forces each
; wrapper to return a negative errno so the normalization macro
; is exercised on every export:
;
;   0 open        — path pointing at a directory that will
;                   never exist ("/proc/libio/does-not-exist-") →
;                   -ENOENT
;   1 openat      — same non-existent path via AT_FDCWD →
;                   -ENOENT
;   2 lseek       — fd=999999 → -EBADF
;   3 pread       — fd=999999 → -EBADF
;   4 pwrite      — fd=999999 → -EBADF
;   5 fstat       — fd=999999 → -EBADF          (v1.1)
;   6 unlink      — bad path  → -ENOENT         (v1.1)
;   7 mkdir       — parent of bad path missing  (v1.1)
;   8 rmdir       — bad path  → -ENOENT         (v1.1)
;
; Prints "PASS\n" and exits 0 when every wrapper returned a
; negative value from its intentionally-broken call. Prints
; "FAIL:<id>\n" and exits 1 on the first wrapper that returned
; a non-negative value.

%define BAD_FD  999999
%define O_RDONLY 0

%ifdef MACOS
%define AT_FDCWD -2
%else
%define AT_FDCWD -100
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern open, openat, lseek, pread, pwrite
extern fstat, unlink, mkdir, rmdir

global _start
global _main

section .rodata
; Path that reliably does not exist on either platform. /proc is
; empty on macOS; the sentinel filename is empty on Linux.
bad_path: db "/proc/libio/does-not-exist-", 0

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
buf:      resb 32

section .text

%macro EXPECT_NEGATIVE 1
    mov byte [fail_id], %1
    test rax, rax
    jns .fail
%endmacro

_start:
_main:
    ; 0: open(bad_path, O_RDONLY, 0) -> -ENOENT
    lea rdi, [bad_path]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    EXPECT_NEGATIVE '0'

    ; 1: openat(AT_FDCWD, bad_path, O_RDONLY, 0) -> -ENOENT
    mov edi, AT_FDCWD
    lea rsi, [bad_path]
    mov edx, O_RDONLY
    xor ecx, ecx
    call openat
    EXPECT_NEGATIVE '1'

    ; 2: lseek(BAD_FD, 0, 0) -> -EBADF
    mov edi, BAD_FD
    xor esi, esi
    xor edx, edx
    call lseek
    EXPECT_NEGATIVE '2'

    ; 3: pread(BAD_FD, buf, 1, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    call pread
    EXPECT_NEGATIVE '3'

    ; 4: pwrite(BAD_FD, buf, 1, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    call pwrite
    EXPECT_NEGATIVE '4'

    ; 5: fstat(BAD_FD, buf) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]                   ; 32-byte buf is smaller than a
                                     ; stat struct, but the kernel
                                     ; never writes to it — EBADF
                                     ; short-circuits before the
                                     ; copyout
    call fstat
    EXPECT_NEGATIVE '5'

    ; 6: unlink(bad_path) -> -ENOENT
    lea rdi, [bad_path]
    call unlink
    EXPECT_NEGATIVE '6'

    ; 7: mkdir(bad_path, 0755) -> -ENOENT (parent /proc/libio/ absent)
    lea rdi, [bad_path]
    mov esi, 0755q
    call mkdir
    EXPECT_NEGATIVE '7'

    ; 8: rmdir(bad_path) -> -ENOENT
    lea rdi, [bad_path]
    call rmdir
    EXPECT_NEGATIVE '8'

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
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall
