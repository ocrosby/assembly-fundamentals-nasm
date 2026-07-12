; file-copy-stream-smoke.asm — v1.15 file_copy_stream round-trip.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; calls libasm's `panic` with "FAIL:<id>\n" and exits
; 1 otherwise. run.sh passes -DSRC_PATH via a mktemp'd name.
;
; The destination fd for `file_copy_stream` is the write end
; of a pipe the smoke creates itself — that gives us a
; verifiable byte stream we can read back with a raw
; sys_read.
;
; Sub-check ids:
;
;   1  Seed src with "HELLO WORLD!" (12 bytes) via raw open +
;      write + close. This fixture setup exercises libio's
;      open and no other library — the whole point of
;      file_copy_stream is that the write side is a caller-
;      provided fd, so we can't use file_write_all to seed.
;   2  pipe(pipefd) → 0. The write end becomes dst_fd; the
;      read end is where we verify.
;   3  file_copy_stream(SRC_PATH, pipefd[1]) → 0.
;   4  Read 12 bytes back from pipefd[0]; byte-compare against
;      "HELLO WORLD!".
;   5  file_copy_stream on a missing path returns -errno,
;      leaving the pipe untouched.
;   6  file_copy_stream on an empty file returns 0 and writes
;      zero bytes (raw read on pipefd[0] with O_NONBLOCK-ish
;      semantics is not available; instead, close the write
;      end and confirm read returns 0 for EOF).

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_read  0x2000003
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%define O_CREAT   0x0200
%define O_TRUNC   0x0400
%else
%define SYS_write 1
%define SYS_read  0
%define SYS_close 3
%define SYS_exit  60
%define O_CREAT   0x40
%define O_TRUNC   0x200
%endif

%define O_WRONLY 1

%ifndef SRC_PATH
%define SRC_PATH "/tmp/libio-file-copy-stream-smoke.src"
%endif
%ifndef EMPTY_SRC_PATH
%define EMPTY_SRC_PATH "/tmp/libio-file-copy-stream-smoke.empty"
%endif
%ifndef MISSING_PATH
%define MISSING_PATH "/proc/libio/does-not-exist-fcs"
%endif

default rel

extern open, file_copy_stream, pipe
extern panic                        ; libasm

global _start
global _main

section .rodata
src_path:       db SRC_PATH, 0
empty_src_path: db EMPTY_SRC_PATH, 0
missing_path:   db MISSING_PATH, 0

msg:      db "HELLO WORLD!"
msg_len:  equ $ - msg               ; 12

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
pipefd:   resd 2
buf16:    resb 16                   ; slack detects overrun

section .text

_start:
_main:
    ; ---- 1: seed src with "HELLO WORLD!" ----
    mov byte [fail_id], '1'
    lea rdi, [src_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov ebx, eax                    ; src_fd

    mov edi, ebx
    lea rsi, [msg]
    mov edx, msg_len
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .seed_ok
    neg rax
.seed_ok:
%endif
    cmp rax, msg_len
    jne .fail

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; Seed empty file for sub-check 6.
    lea rdi, [empty_src_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov edi, eax
    mov rax, SYS_close
    syscall

    ; ---- 2: pipe(pipefd) → 0 ----
    mov byte [fail_id], '2'
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; ---- 3: file_copy_stream(src, pipefd[1]) → 0 ----
    mov byte [fail_id], '3'
    lea rdi, [src_path]
    mov esi, [pipefd + 4]
    call file_copy_stream
    test rax, rax
    jnz .fail

    ; ---- 4: read back 12 bytes, byte-compare ----
    mov byte [fail_id], '4'
    mov edi, [pipefd]
    lea rsi, [buf16]
    mov edx, msg_len
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .read_ok
    neg rax
.read_ok:
%endif
    cmp rax, msg_len
    jne .fail

    lea r9, [buf16]
    lea r10, [msg]
    xor rcx, rcx
.cmp_loop:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, msg_len
    jb .cmp_loop

    ; ---- 5: missing path → negative errno ----
    mov byte [fail_id], '5'
    lea rdi, [missing_path]
    mov esi, [pipefd + 4]
    call file_copy_stream
    test rax, rax
    jns .fail

    ; ---- 6: empty source → 0, and read returns 0 (EOF) ----
    ; file_copy_stream on an empty source performs no write.
    ; Close the write end and verify the read side sees EOF
    ; immediately (no leftover bytes queued).
    mov byte [fail_id], '6'
    lea rdi, [empty_src_path]
    mov esi, [pipefd + 4]
    call file_copy_stream
    test rax, rax
    jnz .fail

    mov edi, [pipefd + 4]
    mov rax, SYS_close
    syscall

    mov edi, [pipefd]
    lea rsi, [buf16]
    mov edx, 4
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .eof_ok
    neg rax
.eof_ok:
%endif
    test rax, rax
    jnz .fail                       ; must be exactly 0 (EOF)

    mov edi, [pipefd]
    mov rax, SYS_close
    syscall

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
    lea rdi, [fail_msg]
    mov esi, fail_len
    call panic
    ; unreachable
