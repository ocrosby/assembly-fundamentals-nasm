; Block SIGPIPE, then write to a pipe with its read end closed
; to trigger SIGPIPE without the process dying. Verify the
; signal was queued via sigpending. Exits 42 on success (bit
; set + write returned -EPIPE); exits 1 on any anomaly.
;
; This is the first runnable example that uses libsig. It
; demonstrates the block / act / observe pattern that is the
; whole point of sigprocmask:
;
;   1. Build a mask with SIGPIPE using sig_zero + sig_add.
;   2. sigprocmask(SIG_BLOCK, mask, NULL) — from now on
;      the kernel queues SIGPIPE instead of delivering it.
;   3. pipe(pipefd) — get a read/write pair.
;   4. close(pipefd[0]) — sever the read side. Any write to
;      pipefd[1] now sees EPIPE.
;   5. write(pipefd[1], msg, len) — returns -EPIPE. The
;      kernel queues SIGPIPE for the calling thread.
;   6. sigpending(pending) → 0. Confirm the SIGPIPE bit
;      is set in the pending set.
;   7. exit(42). We intentionally do not unblock SIGPIPE —
;      that would deliver the queued signal, whose default
;      action is to terminate the process, which would
;      produce exit code 141 (128 + 13) instead of 42.
;
; If SIGPIPE were not blocked, the write in step 5 would kill
; the process with signal 13 before it could reach step 6.
; That is the classic "socket / pipe writer" hazard the
; block-mask pattern exists to prevent.

%include "syscall.inc"

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

extern pipe                         ; libio v1.7
extern sigprocmask, sigpending      ; libsig v1.0
extern sig_zero, sig_add, sig_test  ; libsig v1.1

global _start
global _main

section .rodata
msg:      db "orphaned bytes"
msg_len:  equ $ - msg

section .bss
pipefd:  resd 2                     ; libio's pipe fills two u32s
mask:    resq 1                     ; SIGPIPE-only block set
pending: resq 1                     ; sigpending out slot

section .text

_start:
_main:
    ; ---- Build a SIGPIPE-only mask ----
    ; sig_zero clears the SIGSET_BYTES-sized buffer; sig_add
    ; sets bit (SIGPIPE - 1). Both are pure computation —
    ; no syscall reached yet.
    lea rdi, [mask]
    call sig_zero
    lea rdi, [mask]
    mov esi, SIGPIPE
    call sig_add

    ; ---- sigprocmask(SIG_BLOCK, mask, NULL) ----
    ; From this point on the kernel queues SIGPIPE instead of
    ; delivering it. Any write to a broken pipe will return
    ; -EPIPE and set the pending bit.
    mov edi, SIG_BLOCK
    lea rsi, [mask]
    xor edx, edx                    ; oldset = NULL; not preserved
    call sigprocmask
    test rax, rax
    jnz .fail

    ; ---- pipe(pipefd) ----
    ; libio's wrapper handles the macOS "rax/rdx returns the
    ; two fds" vs Linux "int[2] out slot" difference.
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; ---- close(pipefd[0]) ----
    ; Sever the read end via raw sys_close — close lives in
    ; libsock, which this example does not link (pulling
    ; libsock in for one syscall would obscure the point).
    mov edi, [pipefd]
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_read_ok
    neg rax
.close_read_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- write(pipefd[1], msg, msg_len) → -EPIPE ----
    ; The write end has no reader, so the kernel would send
    ; SIGPIPE. Since SIGPIPE is blocked, the signal is
    ; queued and the syscall returns -EPIPE instead of
    ; terminating the process.
    mov edi, [pipefd + 4]
    lea rsi, [msg]
    mov edx, msg_len
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .write_ok
    neg rax
.write_ok:
%endif
    ; A non-negative return here means the write succeeded,
    ; which contradicts the "read end is closed" setup —
    ; fail the sub-check so the user notices.
    test rax, rax
    jns .fail

    ; ---- sigpending(pending) → 0 ----
    lea rdi, [pending]
    call sigpending
    test rax, rax
    jnz .fail

    ; ---- Confirm SIGPIPE is set in `pending` ----
    ; sig_test returns 1 if bit (sig - 1) is set, 0
    ; otherwise. A 0 here means the kernel did not queue
    ; SIGPIPE for us, which would indicate either a bug in
    ; libsig or a platform difference this example missed.
    lea rdi, [pending]
    mov esi, SIGPIPE
    call sig_test
    cmp rax, 1
    jne .fail

    ; ---- exit(42) ----
    ; Do NOT unblock SIGPIPE — its default action is to
    ; terminate, and delivering a queued SIGPIPE now would
    ; make the process exit 141 (128 + 13) instead of 42.
    ; The pending signal is discarded on exit.
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
