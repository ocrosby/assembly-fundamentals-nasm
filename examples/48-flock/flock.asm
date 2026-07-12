; Show `flock(2)` as a filesystem-backed mutex. Parent opens
; a lock file, acquires LOCK_EX, forks. Child opens the same
; file **separately** (its own open file description),
; attempts LOCK_EX|LOCK_NB, and observes -EWOULDBLOCK
; because the parent holds the lock. Parent then closes
; (releasing the lock). wait4 confirms the child exited 0.
; exit(42).
;
; First runnable that uses libio's `flock`. flock is the
; simplest "process A holds this, process B has to wait"
; primitive that ships on both platforms; every writer of
; a shared file (log rotation, PID files, `/etc/passwd`
; edits) relies on it.
;
; Two separate `open` calls, not a shared fd — flock is
; per open-file-description, not per fd. If the parent and
; child shared the fd via `fork`'s inheritance, they would
; share the lock, and the child's LOCK_NB attempt would
; succeed instead of returning -EWOULDBLOCK.
;
; Program flow:
;
;   parent:
;     open(path, O_RDWR|O_CREAT, 0600)      → parent_fd
;     flock(parent_fd, LOCK_EX)             → 0
;     fork()
;     ├── child:
;     │     open(path, O_RDWR|O_CREAT, 0600) → child_fd (separate)
;     │     flock(child_fd, LOCK_EX|LOCK_NB) → -EWOULDBLOCK
;     │     close(child_fd); _exit(0)
;     └── parent:
;           wait4(child); verify exit == 0
;           close(parent_fd); unlink(path)
;           exit(42)

%include "syscall.inc"

%ifdef MACOS
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%define O_CREAT   0x0200
%define EWOULDBLOCK 35
%else
%define SYS_close 3
%define SYS_exit  60
%define O_CREAT   0x40
%define EWOULDBLOCK 11
%endif

%define O_RDWR    2

default rel

extern open, unlink, flock
extern fork, wait4

global _start
global _main

section .rodata
path: db "/tmp/nasm-flock-mutex.lck", 0

section .bss
wstatus: resq 1

section .text

_start:
_main:
    ; ---- Best-effort cleanup of any leftover lock file ----
    lea rdi, [path]
    call unlink

    ; ---- Parent opens the lock file ----
    lea rdi, [path]
    mov esi, O_RDWR | O_CREAT
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov ebx, eax                            ; parent_fd

    ; ---- Parent acquires LOCK_EX ----
    mov edi, ebx
    mov esi, LOCK_EX
    call flock
    test rax, rax
    jnz .fail

    ; ---- fork ----
    call fork
    test rax, rax
    js .fail
    jz .child

    ; ================================================================
    ; Parent — reap the child, verify it observed -EWOULDBLOCK.
    ; ================================================================
    mov r12d, eax                           ; child pid

    mov edi, r12d
    lea rsi, [wstatus]
    xor edx, edx
    xor ecx, ecx
    call wait4
    test rax, rax
    js .fail

    ; Verify child exited normally with code 0.
    mov eax, [wstatus]
    test eax, 0x7f                          ; low 7 bits = 0 → normal exit
    jnz .fail
    sar eax, 8
    and eax, 0xff
    test eax, eax
    jnz .fail

    ; ---- Cleanup: close (releases lock), unlink ----
    mov edi, ebx
    mov rax, SYS_close
    syscall
    lea rdi, [path]
    call unlink

    ; exit(42)
    mov rax, SYS_exit
    mov edi, 42
    syscall

    ; ================================================================
    ; Child — open the file separately, try LOCK_EX|LOCK_NB.
    ; ================================================================
.child:
    lea rdi, [path]
    mov esi, O_RDWR | O_CREAT
    mov edx, 0600q
    call open
    test rax, rax
    js .child_fail
    mov r12d, eax                           ; child_fd (own open)

    ; Try to acquire the lock non-blocking.
    mov edi, r12d
    mov esi, LOCK_EX | LOCK_NB
    call flock
    ; Expected: -EWOULDBLOCK (parent holds the lock).
    cmp rax, -EWOULDBLOCK
    jne .child_fail

    ; Close (harmless — we do not hold the lock), _exit(0).
    mov edi, r12d
    mov rax, SYS_close
    syscall

    mov rax, SYS_exit
    xor edi, edi
    syscall

.child_fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
