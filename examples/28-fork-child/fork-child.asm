; Fork a child that exits with status 42, wait for it in the
; parent via wait4(), and re-exit with the child's status
; decoded from the wstatus word. Exit 42 on success (proving
; the fork/wait cycle wired end-to-end); exit 1 on any error.
;
; Introduces `libs/proc/libproc.a` and the `fork()` syscall.
; Same pattern as 25-open-socket introducing libsock: swap
; the linked archive on the `ld` line, add an `extern` for the
; new symbol name, done.
;
; Every later example that needs to run a subprocess or drive
; a socket client-and-server pair in one program builds on
; this base — fork is the primitive that makes concurrent
; work-across-processes possible from raw assembly.

%ifdef MACOS
%define SYS_exit    0x2000001
%else
%define SYS_exit    60
%endif

default rel

extern fork, wait4

global _start
global _main

section .bss
wstatus: resd 1

section .text

_start:
_main:
    ; fork() — parent receives the child's pid, child
    ; receives 0. libproc's wrapper normalizes Darwin's
    ; rdx=1 "you are the child" convention to the POSIX
    ; shape so this comparison works uniformly.
    call fork
    test rax, rax
    js .fail                        ; -errno on failure
    jz .child

    ; ---- Parent ----
    ; wait4(child_pid, &wstatus, 0, NULL) — block until the
    ; child exits and reap it. rusage is discarded.
    mov edi, eax                    ; pid (fork's return)
    lea rsi, [wstatus]
    xor edx, edx                    ; options = 0
    xor ecx, ecx                    ; rusage = NULL
    call wait4
    test rax, rax
    js .fail

    ; Decode WEXITSTATUS(wstatus) = (wstatus >> 8) & 0xff and
    ; re-exit with the same code. The CI expected-exit map
    ; asserts this ends up at 42.
    mov eax, [wstatus]
    shr eax, 8
    and eax, 0xff
    mov edi, eax
    mov rax, SYS_exit
    syscall

.child:
    ; ---- Child ----
    ; _exit(42) via a raw syscall — do NOT fall through to any
    ; other path in the file. libc atexit handlers would not
    ; matter here (no libc), but leaving via a distinct exit
    ; site keeps the control flow legible for a reader.
    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
