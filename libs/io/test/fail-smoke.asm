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
;   9 stat        — bad path  → -ENOENT         (v1.2)
;   A rename      — both bad  → -ENOENT         (v1.2)
;   B lstat       — bad path  → -ENOENT         (v1.3)
;   C chmod       — bad path  → -ENOENT         (v1.3)
;   D chown       — bad path  → -ENOENT         (v1.3)
;   E symlink     — dest in missing dir         (v1.3)
;   F readlink    — bad path  → -ENOENT         (v1.3)
;   G truncate    — bad path  → -ENOENT         (v1.3)
;   H ftruncate   — fd=999999 → -EBADF          (v1.3)
;   I getdents    — fd=999999 → -EBADF          (v1.4)
;   J unlinkat    — dirfd=999999 → -EBADF        (v1.5)
;   K mkdirat     — dirfd=999999 → -EBADF        (v1.5)
;   L renameat    — both dirfds bad → -EBADF     (v1.5)
;   M fstatat     — dirfd=999999 → -EBADF        (v1.5)
;   N symlinkat   — dirfd=999999 → -EBADF        (v1.5)
;   O linkat      — both dirfds bad → -EBADF     (v1.5)
;   P readlinkat  — dirfd=999999 → -EBADF        (v1.5)
;   Q fchmodat    — dirfd=999999 → -EBADF        (v1.6)
;   R fchownat    — dirfd=999999 → -EBADF        (v1.6)
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
extern stat, rename
extern lstat, chmod, chown, symlink, readlink, truncate, ftruncate
extern getdents
extern unlinkat, mkdirat, renameat, fstatat, symlinkat, linkat, readlinkat
extern fchmodat, fchownat

global _start
global _main

section .rodata
; Path that reliably does not exist on either platform. /proc is
; empty on macOS; the sentinel filename is empty on Linux.
bad_path:  db "/proc/libio/does-not-exist-", 0
; A second bad path so rename has distinct source and destination.
bad_path2: db "/proc/libio/does-not-exist-b", 0

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

    ; 9: stat(bad_path, buf) -> -ENOENT
    lea rdi, [bad_path]
    lea rsi, [buf]                   ; 32-byte buf — kernel never
                                     ; touches it on the -ENOENT
                                     ; short-circuit
    call stat
    EXPECT_NEGATIVE '9'

    ; A: rename(bad_path, bad_path2) -> -ENOENT
    lea rdi, [bad_path]
    lea rsi, [bad_path2]
    call rename
    EXPECT_NEGATIVE 'A'

    ; B: lstat(bad_path, buf) -> -ENOENT
    lea rdi, [bad_path]
    lea rsi, [buf]
    call lstat
    EXPECT_NEGATIVE 'B'

    ; C: chmod(bad_path, 0644) -> -ENOENT
    lea rdi, [bad_path]
    mov esi, 0644q
    call chmod
    EXPECT_NEGATIVE 'C'

    ; D: chown(bad_path, -1, -1) -> -ENOENT
    lea rdi, [bad_path]
    mov esi, -1
    mov edx, -1
    call chown
    EXPECT_NEGATIVE 'D'

    ; E: symlink(bad_path, bad_path2) -> -ENOENT
    ; symlink accepts arbitrary target strings, but linkpath's
    ; parent must exist — /proc/libio/ does not.
    lea rdi, [bad_path]
    lea rsi, [bad_path2]
    call symlink
    EXPECT_NEGATIVE 'E'

    ; F: readlink(bad_path, buf, 32) -> -ENOENT
    lea rdi, [bad_path]
    lea rsi, [buf]
    mov edx, 32
    call readlink
    EXPECT_NEGATIVE 'F'

    ; G: truncate(bad_path, 0) -> -ENOENT
    lea rdi, [bad_path]
    xor esi, esi
    call truncate
    EXPECT_NEGATIVE 'G'

    ; H: ftruncate(BAD_FD, 0) -> -EBADF
    mov edi, BAD_FD
    xor esi, esi
    call ftruncate
    EXPECT_NEGATIVE 'H'

    ; I: getdents(BAD_FD, buf, 32, &scratch) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 32
    lea rcx, [buf]                   ; position out-slot; scratch
                                     ; reuse — kernel writes are
                                     ; short-circuited by EBADF
    call getdents
    EXPECT_NEGATIVE 'I'

    ; J: unlinkat(BAD_FD, bad_path, 0) -> -EBADF
    ; bad_path is absolute but the kernel checks BAD_FD first
    ; on both platforms — the errno is deterministic.
    mov edi, BAD_FD
    lea rsi, [bad_path]
    xor edx, edx
    call unlinkat
    EXPECT_NEGATIVE 'J'

    ; K: mkdirat(BAD_FD, bad_path, 0755) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    mov edx, 0755q
    call mkdirat
    EXPECT_NEGATIVE 'K'

    ; L: renameat(BAD_FD, bad_path, BAD_FD, bad_path2) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    mov edx, BAD_FD
    lea rcx, [bad_path2]
    call renameat
    EXPECT_NEGATIVE 'L'

    ; M: fstatat(BAD_FD, bad_path, buf, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    lea rdx, [buf]
    xor ecx, ecx
    call fstatat
    EXPECT_NEGATIVE 'M'

    ; N: symlinkat(bad_path, BAD_FD, bad_path2) -> -EBADF
    lea rdi, [bad_path]
    mov esi, BAD_FD
    lea rdx, [bad_path2]
    call symlinkat
    EXPECT_NEGATIVE 'N'

    ; O: linkat(BAD_FD, bad_path, BAD_FD, bad_path2, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    mov edx, BAD_FD
    lea rcx, [bad_path2]
    xor r8d, r8d
    call linkat
    EXPECT_NEGATIVE 'O'

    ; P: readlinkat(BAD_FD, bad_path, buf, 32) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    lea rdx, [buf]
    mov ecx, 32
    call readlinkat
    EXPECT_NEGATIVE 'P'

    ; Q: fchmodat(BAD_FD, bad_path, 0644, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    mov edx, 0644q
    xor ecx, ecx
    call fchmodat
    EXPECT_NEGATIVE 'Q'

    ; R: fchownat(BAD_FD, bad_path, -1, -1, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [bad_path]
    mov edx, -1
    mov ecx, -1
    xor r8d, r8d
    call fchownat
    EXPECT_NEGATIVE 'R'

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
