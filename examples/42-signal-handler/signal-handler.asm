; Install a custom SIGPIPE handler (Linux only, via libsig
; v1.3's `sig_restorer` trampoline), then trigger SIGPIPE
; three times by writing to a pipe whose read end is closed.
; The handler increments a counter; the parent verifies the
; counter reached 3 before exiting. macOS falls back to
; SIG_IGN (libsig v1.2) and counts -EPIPE returns instead —
; the same round-trip observation, just from the syscall
; return rather than a handler state. Both platforms exit 42.
;
; First runnable that uses v1.3's `sig_restorer` trampoline
; end to end. Where 38-signal-block used sigprocmask to
; queue SIGPIPE and only observed pending, this example
; **catches** the delivery in a handler function that runs
; and returns normally — the whole point of shipping a real
; trampoline.
;
; Program flow:
;
;   Linux:
;       act.sa_handler = increment
;       act.sa_flags  |= SA_RESTORER
;       act.sa_restorer = sig_restorer
;       sigaction(SIGPIPE, act, NULL)         → 0
;       pipe(pipefd); close(pipefd[0])
;       for i in 0..2:
;           write(pipefd[1], "x", 1)          → -EPIPE
;           ; handler runs, counter += 1
;       assert counter == 3
;       exit(42)
;
;   macOS:
;       act.sa_handler = SIG_IGN
;       sigaction(SIGPIPE, act, NULL)         → 0
;       pipe(pipefd); close(pipefd[0])
;       counter = 0
;       for i in 0..2:
;           write(pipefd[1], "x", 1)          → -EPIPE
;           counter += 1                       (from -EPIPE, not handler)
;       assert counter == 3
;       exit(42)
;
; Introduces:
;
; - **`sig_restorer` (libsig v1.3, Linux).** The SA_RESTORER
;   trampoline that lets a handler function `ret` cleanly.
;   Without it the handler's return address is garbage from
;   the signal frame and the process crashes.
; - **Handler + observation pattern.** Rather than blocking
;   the signal and querying `sigpending` (38-signal-block),
;   this example installs a real handler and observes the
;   handler's side effects. Idiomatic on Linux; the macOS
;   fallback uses the syscall return for the same
;   information until libsig grows sa_tramp support.

%include "syscall.inc"                  ; libsig — SIG_IGN, SIGPIPE, SA_RESTORER

%ifdef MACOS
%define SYS_write   0x2000004
%define SYS_close   0x2000006
%define SYS_exit    0x2000001
%else
%define SYS_write   1
%define SYS_close   3
%define SYS_exit    60
%endif

default rel

extern pipe                             ; libio
extern sigaction                        ; libsig v1.2
%ifndef MACOS
extern sig_restorer                     ; libsig v1.3 Linux trampoline
%endif

global _start
global _main

section .rodata
one_byte: db "x"

section .bss
pipefd:   resd 2
act:      resb SIGACTION_SIZE
counter:  resb 1

section .text

_start:
_main:
    ; ---- Install the disposition ----
    ; On Linux the disposition is a real handler function; on
    ; macOS it is SIG_IGN. The struct sigaction fields land at
    ; different offsets per platform (see libsig syscall.inc).
%ifdef MACOS
    mov qword [act + SA_HANDLER_OFF], SIG_IGN
%else
    lea rax, [handler]
    mov [act + SA_HANDLER_OFF], rax
    mov qword [act + SA_FLAGS_OFF], SA_RESTORER
    lea rax, [sig_restorer]
    mov [act + SA_RESTORER_OFF], rax
%endif
    mov edi, SIGPIPE
    lea rsi, [act]
    xor edx, edx
    call sigaction
    test rax, rax
    jnz .fail

    ; ---- pipe(pipefd); close(pipefd[0]) ----
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    mov edi, [pipefd]
    mov rax, SYS_close
    syscall

    ; ---- Loop: three writes to the broken pipe ----
    ; Each write raises SIGPIPE. On Linux the handler runs
    ; and increments `counter`. On macOS the signal is
    ; ignored and the syscall returns -EPIPE; we increment
    ; `counter` explicitly from the caller side.
    mov r12d, 3                         ; iterations remaining
.write_loop:
    mov edi, [pipefd + 4]
    lea rsi, [one_byte]
    mov edx, 1
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .w_norm
    neg rax
.w_norm:
    ; Increment counter on the -EPIPE return, mirroring what
    ; the Linux handler does natively.
    test rax, rax
    jns .fail                           ; write should have failed
    inc byte [counter]
%endif
    dec r12d
    jnz .write_loop

    ; ---- Verify counter == 3 ----
    cmp byte [counter], 3
    jne .fail

    ; ---- Cleanup: close the write end and exit(42) ----
    mov edi, [pipefd + 4]
    mov rax, SYS_close
    syscall
    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall

%ifndef MACOS
; ---- Custom SIGPIPE handler (Linux only) ----
; Signature: void handler(int sig). The trampoline installs
; the handler at kernel-delivery time; the kernel calls it
; with the signal number in rdi. The handler bumps the
; counter and returns; sig_restorer then invokes
; SYS_rt_sigreturn to unwind the signal frame.
;
; Must be defined AFTER `.fail:` — NASM local labels scope
; to the previous non-local label, so putting `handler:`
; between the body and `.fail:` would rebind `.fail` to
; `handler.fail` and break the many `jnz .fail` jumps above.
handler:
    inc byte [counter]
    ret
%endif
