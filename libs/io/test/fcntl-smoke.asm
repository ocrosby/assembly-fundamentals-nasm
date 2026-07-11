; fcntl-smoke.asm — v1.8 fcntl + flock coverage.
;
; Standalone. Uses pipe (v1.7) as its fd fixture so both fcntl
; paths can be exercised in one process without socket helpers.
;
; Sub-check ids:
;
;   1  pipe(pipefd) → 0 (needed for every sub-check below)
;   2  fcntl(pipefd[0], F_GETFL, 0)                 → non-negative
;   3  fcntl(pipefd[0], F_SETFL, old|O_NONBLOCK)    → 0
;   4  fcntl(pipefd[0], F_GETFL, 0) has O_NONBLOCK bit set
;   5  read(pipefd[0], buf, 1) via raw syscall      → -EAGAIN
;      (proves the flag actually reached the kernel)
;   6  fcntl(pipefd[0], F_GETFD, 0)                 → non-negative
;   7  fcntl(pipefd[0], F_SETFD, FD_CLOEXEC)        → 0
;   8  fcntl(pipefd[0], F_GETFD, 0) has FD_CLOEXEC set
;   9  open a scratch tempfile TMPFILE_LOCK        → fd
;   A  flock(fd, LOCK_EX | LOCK_NB)                 → 0
;   B  flock(fd, LOCK_UN)                           → 0
;   C  close(fd); unlink(TMPFILE_LOCK); close pipe

%ifndef TMPFILE_LOCK
%define TMPFILE_LOCK "/tmp/libio-fcntl-smoke-default"
%endif

; O_* flags for open() below. Only the platform-varying
; O_CREAT is redefined per-platform; the fixed low-bit values
; (O_RDONLY = 0, O_RDWR = 2) agree.
%define O_RDWR      2
%ifdef MACOS
%define O_CREAT     0x200
%else
%define O_CREAT     0x40
%endif

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_read  0x2000003
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_read  0
%define SYS_close 3
%define SYS_exit  60
%endif

default rel

extern pipe, fcntl, flock, open, unlink

global _start
global _main

section .rodata
tmpfile_lock: db TMPFILE_LOCK, 0
pass_msg:     db "PASS", 10
pass_len:     equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
pipefd:   resd 2
buf:      resb 4

section .text

; RAW_CLOSE — inline close via raw syscall + macOS neg-rax
; normalization.
%macro RAW_CLOSE 0
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc %%ok
    neg rax
%%ok:
%endif
%endmacro

_start:
_main:
    ; ---- 1: pipe(pipefd) → 0 ----
    mov byte [fail_id], '1'
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; ---- 2: fcntl(pipefd[0], F_GETFL, 0) → non-negative ----
    mov byte [fail_id], '2'
    mov edi, [pipefd]
    mov esi, F_GETFL
    xor edx, edx
    call fcntl
    test rax, rax
    js .fail
    mov r12d, eax                    ; save old flags for step 3

    ; ---- 3: fcntl(pipefd[0], F_SETFL, old | O_NONBLOCK) → 0 ----
    mov byte [fail_id], '3'
    mov edi, [pipefd]
    mov esi, F_SETFL
    mov edx, r12d
    or edx, O_NONBLOCK
    call fcntl
    test rax, rax
    jnz .fail

    ; ---- 4: F_GETFL now has O_NONBLOCK ----
    mov byte [fail_id], '4'
    mov edi, [pipefd]
    mov esi, F_GETFL
    xor edx, edx
    call fcntl
    test rax, rax
    js .fail
    test eax, O_NONBLOCK
    jz .fail

    ; ---- 5: read from empty non-blocking pipe → -EAGAIN ----
    mov byte [fail_id], '5'
    mov edi, [pipefd]
    lea rsi, [buf]
    mov edx, 1
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .read_ok
    neg rax
.read_ok:
%endif
    test rax, rax
    jns .fail                        ; want strictly negative

    ; ---- 6: fcntl(pipefd[0], F_GETFD, 0) → non-negative ----
    mov byte [fail_id], '6'
    mov edi, [pipefd]
    mov esi, F_GETFD
    xor edx, edx
    call fcntl
    test rax, rax
    js .fail

    ; ---- 7: fcntl(pipefd[0], F_SETFD, FD_CLOEXEC) → 0 ----
    mov byte [fail_id], '7'
    mov edi, [pipefd]
    mov esi, F_SETFD
    mov edx, FD_CLOEXEC
    call fcntl
    test rax, rax
    jnz .fail

    ; ---- 8: F_GETFD now has FD_CLOEXEC ----
    mov byte [fail_id], '8'
    mov edi, [pipefd]
    mov esi, F_GETFD
    xor edx, edx
    call fcntl
    test eax, FD_CLOEXEC
    jz .fail

    ; ---- 9: open(TMPFILE_LOCK, O_RDWR|O_CREAT, 0644) → fd ----
    mov byte [fail_id], '9'
    lea rdi, [tmpfile_lock]
    mov esi, O_RDWR | O_CREAT
    mov edx, 0644q
    call open
    test rax, rax
    js .fail
    mov r13, rax                     ; lock fd

    ; ---- A: flock(fd, LOCK_EX | LOCK_NB) → 0 ----
    mov byte [fail_id], 'A'
    mov rdi, r13
    mov esi, LOCK_EX | LOCK_NB
    call flock
    test rax, rax
    jnz .fail

    ; ---- B: flock(fd, LOCK_UN) → 0 ----
    mov byte [fail_id], 'B'
    mov rdi, r13
    mov esi, LOCK_UN
    call flock
    test rax, rax
    jnz .fail

    ; ---- C: close everything and unlink the tempfile ----
    mov byte [fail_id], 'C'
    mov rdi, r13
    RAW_CLOSE
    test rax, rax
    jnz .fail
    lea rdi, [tmpfile_lock]
    call unlink
    test rax, rax
    jnz .fail
    mov edi, [pipefd]
    RAW_CLOSE
    test rax, rax
    jnz .fail
    mov edi, [pipefd + 4]
    RAW_CLOSE
    test rax, rax
    jnz .fail

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
