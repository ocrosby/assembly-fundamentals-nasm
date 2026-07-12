; file-write-all-smoke.asm — v1.13 file_write_all round-trip.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; calls libasm's `panic` with "FAIL:<id>\n" and exits
; 1 otherwise. run.sh passes -DDST_PATH / -DEMPTY_DST_PATH via
; mktemp'd names.
;
; Sub-check ids:
;
;   1  file_write_all(DST, msg, 12) returns 0.
;   2  Read the resulting file back via raw read + compare —
;      buf must hold exactly "HELLO WORLD!" in bytes 0..11.
;   3  Re-run with the same DST path — file gets truncated.
;      Write "PING", read back, verify exactly 4 bytes.
;   4  file_write_all on a bad path (non-existent parent
;      directory) returns negative errno.
;   5  file_write_all(EMPTY_DST, addr, 0) returns 0 and the
;      resulting file has size 0 (io_size proves it).

%include "syscall.inc"

%ifdef MACOS
%define SYS_read  0x2000003
%define SYS_write 0x2000004
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%else
%define SYS_read  0
%define SYS_write 1
%define SYS_close 3
%define SYS_exit  60
%endif

%define O_RDONLY 0

%ifndef DST_PATH
%define DST_PATH "/tmp/libio-file-write-all-smoke.dst"
%endif
%ifndef EMPTY_DST_PATH
%define EMPTY_DST_PATH "/tmp/libio-file-write-all-smoke.empty"
%endif
%ifndef BAD_PATH
%define BAD_PATH "/proc/libio/does-not-exist-fwa/child"
%endif

default rel

extern open, io_size, file_write_all
extern panic                        ; libasm

global _start
global _main

section .rodata
dst_path:       db DST_PATH, 0
empty_dst_path: db EMPTY_DST_PATH, 0
bad_path:       db BAD_PATH, 0

msg:      db "HELLO WORLD!"
msg_len:  equ $ - msg               ; 12

msg2:     db "PING"
msg2_len: equ $ - msg2               ; 4

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
buf16:    resb 16                   ; slack detects overrun
size_out: resq 1

section .text

_start:
_main:
    ; ---- 1: file_write_all(DST, msg, 12) → 0 ----
    mov byte [fail_id], '1'
    lea rdi, [dst_path]
    lea rsi, [msg]
    mov rdx, msg_len
    call file_write_all
    test rax, rax
    jnz .fail

    ; ---- 2: read back and byte-compare against msg ----
    mov byte [fail_id], '2'
    lea rdi, [dst_path]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .fail
    mov ebx, eax                    ; fd

    mov edi, ebx
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

    ; Byte-by-byte compare — spelled out so this smoke does
    ; not force libstr into libio's test dep graph.
    lea r9, [buf16]
    lea r10, [msg]
    xor rcx, rcx
.cmp_loop1:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, msg_len
    jb .cmp_loop1

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; ---- 3: re-run truncates; write shorter payload, verify ----
    mov byte [fail_id], '3'
    lea rdi, [dst_path]
    lea rsi, [msg2]
    mov rdx, msg2_len
    call file_write_all
    test rax, rax
    jnz .fail

    lea rdi, [dst_path]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .fail
    mov ebx, eax

    ; io_size must report exactly msg2_len — proves the
    ; O_TRUNC on the second open shrank the file.
    mov edi, ebx
    lea rsi, [size_out]
    call io_size
    test rax, rax
    jnz .fail
    cmp qword [size_out], msg2_len
    jne .fail

    mov edi, ebx
    lea rsi, [buf16]
    mov edx, msg2_len
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .read2_ok
    neg rax
.read2_ok:
%endif
    cmp rax, msg2_len
    jne .fail

    lea r9, [buf16]
    lea r10, [msg2]
    xor rcx, rcx
.cmp_loop2:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, msg2_len
    jb .cmp_loop2

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; ---- 4: bad path (missing parent dir) → -errno ----
    mov byte [fail_id], '4'
    lea rdi, [bad_path]
    lea rsi, [msg]
    mov rdx, msg_len
    call file_write_all
    test rax, rax
    jns .fail                       ; want strictly negative

    ; ---- 5: size = 0 succeeds and produces an empty file ----
    mov byte [fail_id], '5'
    lea rdi, [empty_dst_path]
    lea rsi, [msg]                  ; addr is irrelevant when size=0
    xor rdx, rdx
    call file_write_all
    test rax, rax
    jnz .fail

    lea rdi, [empty_dst_path]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .fail
    mov ebx, eax
    mov edi, ebx
    lea rsi, [size_out]
    call io_size
    test rax, rax
    jnz .fail
    cmp qword [size_out], 0
    jne .fail
    mov edi, ebx
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
