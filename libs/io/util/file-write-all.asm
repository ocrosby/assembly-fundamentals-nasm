; file_write_all(path, addr, size) -> 0 or -errno
;
; Writes `size` bytes from `[addr]` into a fresh file at
; `path`, handling short writes internally. The symmetric
; counterpart to `file_read_all` (v1.12) — that one hands the
; caller a mmap'd view of a whole file; this one dumps a
; caller-owned buffer as a whole file.
;
; Program flow:
;
;   open(path, O_WRONLY|O_CREAT|O_TRUNC, 0600)   → fd
;   while written < size:
;       n = write(fd, addr + written, size - written)
;       if n < 0: close(fd); return n
;       written += n
;   close(fd)
;   return 0
;
; Semantics:
;   * `path` is created if missing, truncated if present. Mode
;     bits are 0600 (owner read/write, group/other none) —
;     matching `file_copy` and `file_read_all`'s destination
;     conventions.
;   * `size == 0` is legal. The routine still opens (creating
;     or truncating the file) and closes; no write syscall runs.
;   * Short writes are looped in userspace (matching libsock's
;     `send_all` pattern). Any error terminates the loop and
;     the negative errno propagates through the close cleanup.
;
; The write is issued via a raw `SYS_write` syscall — libio
; deliberately does not export `write` (it lives in libsock,
; and pulling libsock in for one syscall would push libio's
; dep graph the wrong direction). `SYS_close` is inlined for
; the same reason.
;
; Callee-saved registers used:
;   rbx  fd (u32 in low bits)
;   r12  addr (source pointer; reused as errno scratch on
;        the error unwind after the loop no longer needs it)
;   r13  total size
;   r14  bytes written so far

%include "syscall.inc"

%define O_WRONLY 1

%ifdef MACOS
%define O_CREAT     0x0200
%define O_TRUNC     0x0400
%define SYS_write   0x2000004
%define SYS_close   0x2000006
%else
%define O_CREAT     0x40
%define O_TRUNC     0x200
%define SYS_write   1
%define SYS_close   3
%endif

default rel

extern open

global file_write_all

section .text

file_write_all:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8                      ; align rsp for the open call

    mov r12, rsi                    ; save addr
    mov r13, rdx                    ; save size

    ; ---- open(path, O_WRONLY|O_CREAT|O_TRUNC, 0600) ----
    ; rdi already = path.
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .done                        ; nothing opened; return -errno
    mov ebx, eax                    ; fd

    xor r14, r14                    ; bytes written so far

.write_loop:
    ; Done when written == size. Handles size == 0 on the
    ; very first iteration (no write syscall runs).
    cmp r14, r13
    je .close_ok

    ; ---- write(fd, addr + written, remaining) ----
    mov edi, ebx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14                    ; remaining bytes
    mov rax, SYS_write
    SYSCALL_NORM
    test rax, rax
    js .close_err

    add r14, rax                    ; advance by however many landed
    jmp .write_loop

.close_ok:
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    xor eax, eax                    ; return 0
    jmp .done

.close_err:
    ; -errno in rax. r12 (addr) is no longer needed; reuse
    ; it as scratch to hold the errno across the raw close.
    mov r12, rax
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    mov rax, r12
    ; fall through

.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
