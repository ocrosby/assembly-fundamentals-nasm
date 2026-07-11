; fdgraph-smoke.asm — v1.7 smoke covering libio's fd-graph
; wrappers: dup, dup2, and pipe.
;
; The main io-smoke has exhausted its single-character sub-check
; ID space (1..9, A..Z, a..y) so v1.7 goes into a dedicated
; smoke rather than piling on cryptic punctuation IDs.
;
; Sequence:
;
;   1  pipe(pipefd) → 0; both fds are strictly positive
;   2  write(pipefd[1], "hi", 2) via raw syscall → 2
;      (libio does not export write; libsock does, but pulling
;      libsock in just for a two-byte write would confuse the
;      coverage story — the raw syscall matches how io-smoke
;      already handles close)
;   3  read(pipefd[0], buf, 2) → 2, buf[0..1] == "hi"
;   4  dup(pipefd[0]) → positive fd distinct from the source
;   5  close(dup'd fd) via raw syscall
;   6  dup2(pipefd[0], 50) → 50
;   7  close(50) via raw syscall
;   8  close(pipefd[0]) and close(pipefd[1]) via raw syscall
;   9  dup(BAD_FD) → negative errno
;      (proves the wrappers propagate rather than swallow)

%define BAD_FD 999999

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

extern dup, dup2, pipe

global _start
global _main

section .rodata
hi:       db "hi"
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
pipefd:   resd 2                     ; pipe writes 2 fds here
buf:      resb 4

section .text

; ---- helpers ----------------------------------------------
; raw_close(rdi=fd) — inline close via raw syscall + macOS
; carry-flag normalization. Returns rax = 0 or -errno.
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
    ; ---- 1: pipe(pipefd) → 0; both fds > 0 ----
    mov byte [fail_id], '1'
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail
    mov eax, [pipefd]
    test eax, eax
    js .fail
    mov eax, [pipefd + 4]
    test eax, eax
    js .fail

    ; ---- 2: write(pipefd[1], "hi", 2) via raw syscall ----
    mov byte [fail_id], '2'
    mov edi, [pipefd + 4]
    lea rsi, [hi]
    mov edx, 2
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .write_ok
    neg rax
.write_ok:
%endif
    cmp rax, 2
    jne .fail

    ; ---- 3: read(pipefd[0], buf, 2); buf == "hi" ----
    mov byte [fail_id], '3'
    mov edi, [pipefd]
    lea rsi, [buf]
    mov edx, 2
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .read_ok
    neg rax
.read_ok:
%endif
    cmp rax, 2
    jne .fail
    mov ax, [buf]                    ; 2-byte compare against "hi"
    cmp ax, 0x6968                   ; 'h' (0x68) at low, 'i' (0x69) at high
    jne .fail

    ; ---- 4: dup(pipefd[0]) → positive fd, distinct value ----
    mov byte [fail_id], '4'
    mov edi, [pipefd]
    call dup
    test rax, rax
    js .fail
    mov r13d, eax                    ; save dup'd fd
    cmp eax, [pipefd]
    je .fail                         ; should be a NEW fd number

    ; ---- 5: close(dup'd fd) ----
    mov byte [fail_id], '5'
    mov edi, r13d
    RAW_CLOSE
    test rax, rax
    jnz .fail

    ; ---- 6: dup2(pipefd[0], 50) → 50 ----
    mov byte [fail_id], '6'
    mov edi, [pipefd]
    mov esi, 50
    call dup2
    cmp rax, 50
    jne .fail

    ; ---- 7: close(50) ----
    mov byte [fail_id], '7'
    mov edi, 50
    RAW_CLOSE
    test rax, rax
    jnz .fail

    ; ---- 8: close both pipe ends ----
    mov byte [fail_id], '8'
    mov edi, [pipefd]
    RAW_CLOSE
    test rax, rax
    jnz .fail
    mov edi, [pipefd + 4]
    RAW_CLOSE
    test rax, rax
    jnz .fail

    ; ---- 9: dup(BAD_FD) → negative errno ----
    mov byte [fail_id], '9'
    mov edi, BAD_FD
    call dup
    test rax, rax
    jns .fail                        ; want strictly negative

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
