; file-copy-smoke.asm — v1.11 file_copy round-trip.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; calls libasm's `panic` with "FAIL:<id>\n" and exits
; 1 otherwise. Requires the caller (run.sh) to pass -DSRC_PATH
; and -DDST_PATH via mktemp'd names.
;
; Sub-check ids:
;
;   1  Seed src with "HELLO WORLD!" via open + write + close
;      (raw syscalls — this fixture setup is not exercising
;      libio, so keeping it inline avoids pulling in extra
;      wrappers).
;   2  file_copy(SRC_PATH, DST_PATH) returns 0.
;   3  Reopen dst and read back 12 bytes; memcmp against the
;      expected "HELLO WORLD!" reference returns 0.
;   4  file_copy on a missing source path returns negative
;      errno (proves error propagation through the composed
;      helper).
;   5  file_copy of a zero-length source produces a zero-length
;      destination — verifies the mmap short-circuit.

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

%define O_RDONLY 0
%define O_WRONLY 1

%ifndef SRC_PATH
%define SRC_PATH "/tmp/libio-file-copy-smoke.src"
%endif
%ifndef DST_PATH
%define DST_PATH "/tmp/libio-file-copy-smoke.dst"
%endif
%ifndef EMPTY_SRC_PATH
%define EMPTY_SRC_PATH "/tmp/libio-file-copy-smoke.empty-src"
%endif
%ifndef EMPTY_DST_PATH
%define EMPTY_DST_PATH "/tmp/libio-file-copy-smoke.empty-dst"
%endif
%ifndef MISSING_PATH
%define MISSING_PATH "/proc/libio/does-not-exist-cp"
%endif

default rel

extern open, io_size, file_copy
extern panic                        ; libasm

global _start
global _main

section .rodata
src_path:        db SRC_PATH, 0
dst_path:        db DST_PATH, 0
empty_src_path:  db EMPTY_SRC_PATH, 0
empty_dst_path:  db EMPTY_DST_PATH, 0
missing_path:    db MISSING_PATH, 0
missing_dst:     db "/tmp/libio-file-copy-smoke.wontbe-created", 0

msg:             db "HELLO WORLD!"
msg_len:         equ $ - msg        ; 12

pass_msg:        db "PASS", 10
pass_len:        equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
buf12:  resb 16                     ; 4 bytes slack detects overrun
size_out: resq 1                    ; io_size out slot for sub-check 5

section .text

_start:
_main:
    ; ---- 1: seed src file with "HELLO WORLD!" ----
    mov byte [fail_id], '1'
    ; open(src_path, O_WRONLY|O_CREAT|O_TRUNC, 0600)
    lea rdi, [src_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov ebx, eax                    ; src_fd

    ; write(src_fd, msg, msg_len)
    mov edi, ebx
    lea rsi, [msg]
    mov edx, msg_len
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .seed_write_ok
    neg rax
.seed_write_ok:
%endif
    cmp rax, msg_len
    jne .fail

    ; close(src_fd)
    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; Also seed an empty source for sub-check 5.
    lea rdi, [empty_src_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov edi, eax
    mov rax, SYS_close
    syscall

    ; ---- 2: file_copy(SRC_PATH, DST_PATH) → 0 ----
    mov byte [fail_id], '2'
    lea rdi, [src_path]
    lea rsi, [dst_path]
    call file_copy
    test rax, rax
    jnz .fail

    ; ---- 3: read dst back, memcmp against msg ----
    mov byte [fail_id], '3'
    lea rdi, [dst_path]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .fail
    mov ebx, eax                    ; dst_fd

    mov edi, ebx
    lea rsi, [buf12]
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

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; Compare buf12 vs msg — spelled out as a byte loop so this
    ; smoke does not force libstr into libio's dep graph.
    lea r9, [buf12]
    lea r10, [msg]
    xor rcx, rcx
.cmp_loop:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, msg_len
    jb .cmp_loop

    ; ---- 4: file_copy(MISSING_PATH, missing_dst) → -errno ----
    mov byte [fail_id], '4'
    lea rdi, [missing_path]
    lea rsi, [missing_dst]
    call file_copy
    test rax, rax
    jns .fail                       ; want strictly negative

    ; ---- 5: file_copy of empty source produces empty dst ----
    mov byte [fail_id], '5'
    lea rdi, [empty_src_path]
    lea rsi, [empty_dst_path]
    call file_copy
    test rax, rax
    jnz .fail
    ; Open the empty destination and check its size == 0 via
    ; io_size. Any nonzero size (or open failure) fails the
    ; sub-check.
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
