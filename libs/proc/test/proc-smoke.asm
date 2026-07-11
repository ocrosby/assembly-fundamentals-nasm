; proc-smoke.asm — v1.0 fork / wait4 / getpid / getppid / kill.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; prints "FAIL:<id>\n" to stderr and exits 1 otherwise.
;
; Sub-check ids:
;
;   1  getpid()  > 0                     (any real process has pid > 0)
;   2  getppid() > 0                     (a smoke test is never pid 1)
;   3  getppid() != getpid()             (parent-of-self is impossible)
;   4  fork() >= 0                       (both branches of a healthy fork)
;   5  child: immediately _exit(42)      (raw syscall — no libc)
;   6  parent: fork return value > 0     (must be positive pid)
;   7  parent: wait4(child_pid, ...)     returns child_pid
;   8  parent: wstatus == 42 << 8        (WIFEXITED and WEXITSTATUS=42)
;   9  parent: kill(child_pid, 0) → -ESRCH (child already reaped)

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%define ESRCH     -3            ; canonical -3 on both platforms
%else
%define SYS_write 1
%define SYS_exit  60
%define ESRCH     -3
%endif

default rel

extern fork, wait4, getpid, getppid, kill

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
wstatus: resq 1
saved_child_pid: resq 1

section .text

_start:
_main:
    ; ---- 1: getpid() > 0 ----
    mov byte [fail_id], '1'
    call getpid
    test rax, rax
    jle .fail
    mov r12, rax                     ; save my pid for later checks

    ; ---- 2: getppid() > 0 ----
    mov byte [fail_id], '2'
    call getppid
    test rax, rax
    jle .fail
    mov r13, rax                     ; save my parent's pid

    ; ---- 3: getppid() != getpid() ----
    mov byte [fail_id], '3'
    cmp r12, r13
    je .fail

    ; ---- 4: fork() >= 0 ----
    mov byte [fail_id], '4'
    call fork
    test rax, rax
    js .fail                         ; negative = errno

    ; Branch on rax: 0 → child, >0 → parent.
    test rax, rax
    jz .child

    ; ---- Parent path ----
.parent:
    ; ---- 6: fork return value > 0 in parent ----
    mov byte [fail_id], '6'
    test rax, rax
    jle .fail
    mov [saved_child_pid], rax

    ; ---- 7: wait4(child_pid, &wstatus, 0, NULL) → child_pid ----
    mov byte [fail_id], '7'
    mov rdi, [saved_child_pid]
    lea rsi, [wstatus]
    xor edx, edx                     ; options = 0 (blocking)
    xor ecx, ecx                     ; rusage* = NULL
    call wait4
    mov rbx, [saved_child_pid]
    cmp rax, rbx
    jne .fail

    ; ---- 8: wstatus == 42 << 8  (WIFEXITED && WEXITSTATUS=42) ----
    mov byte [fail_id], '8'
    mov rax, [wstatus]
    cmp rax, 42 << 8
    jne .fail

    ; ---- 9: kill(child_pid, 0) → -ESRCH ----
    mov byte [fail_id], '9'
    mov rdi, [saved_child_pid]
    xor esi, esi                     ; sig = 0 (permission-check)
    call kill
    cmp rax, ESRCH
    jne .fail

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

    ; ---- Child path ----
.child:
    ; ---- 5: _exit(42) via raw syscall — do NOT call any libc,
    ; and do NOT call the shared .fail path (parent's stdout
    ; would end up with a bogus FAIL line). ----
    mov rax, SYS_exit
    mov edi, 42
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
