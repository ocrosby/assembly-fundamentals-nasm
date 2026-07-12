; file-read-all-smoke.asm — v1.12 file_read_all round-trip.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; calls libasm's `panic` with "FAIL:<id>\n" and exits
; 1 otherwise. run.sh passes -DSRC_PATH / -DEMPTY_SRC_PATH
; via mktemp'd names.
;
; Sub-check ids:
;
;   1  Seed src with "HELLO WORLD!" via raw open + write + close.
;      An empty companion file is seeded via open + close.
;   2  file_read_all(SRC_PATH, &addr, &size) returns 0.
;   3  size == 12 and addr is non-NULL.
;   4  Byte-by-byte compare against the reference "HELLO WORLD!" —
;      proves the mapping actually contains the file's bytes.
;   5  munmap(addr, size) returns 0 — caller owns the mapping.
;   6  file_read_all on a missing path returns negative errno.
;   7  file_read_all on an empty file returns 0, size == 0, addr
;      is NULL (proves the zero-length short-circuit does not
;      leak an mmap for len=0).

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%define O_CREAT   0x0200
%define O_TRUNC   0x0400
%else
%define SYS_write 1
%define SYS_close 3
%define SYS_exit  60
%define O_CREAT   0x40
%define O_TRUNC   0x200
%endif

%define O_WRONLY 1

%ifndef SRC_PATH
%define SRC_PATH "/tmp/libio-file-read-all-smoke.src"
%endif
%ifndef EMPTY_SRC_PATH
%define EMPTY_SRC_PATH "/tmp/libio-file-read-all-smoke.empty"
%endif
%ifndef MISSING_PATH
%define MISSING_PATH "/proc/libio/does-not-exist-fra"
%endif

default rel

extern open, munmap, file_read_all
extern panic                        ; libasm

global _start
global _main

section .rodata
src_path:       db SRC_PATH, 0
empty_src_path: db EMPTY_SRC_PATH, 0
missing_path:   db MISSING_PATH, 0

msg:      db "HELLO WORLD!"
msg_len:  equ $ - msg

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
out_addr: resq 1                    ; file_read_all writes mapping addr here
out_size: resq 1                    ; file_read_all writes size here

section .text

_start:
_main:
    ; ---- 1: seed src with "HELLO WORLD!" plus an empty file ----
    mov byte [fail_id], '1'
    ; open(src, O_WRONLY|O_CREAT|O_TRUNC, 0600)
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
    jnc .seed_write_ok
    neg rax
.seed_write_ok:
%endif
    cmp rax, msg_len
    jne .fail

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; Empty file: open+close leaves it size 0.
    lea rdi, [empty_src_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov edi, eax
    mov rax, SYS_close
    syscall

    ; ---- 2: file_read_all(SRC_PATH, &out_addr, &out_size) → 0 ----
    mov byte [fail_id], '2'
    lea rdi, [src_path]
    lea rsi, [out_addr]
    lea rdx, [out_size]
    call file_read_all
    test rax, rax
    jnz .fail

    ; ---- 3: size == 12, addr non-NULL ----
    mov byte [fail_id], '3'
    cmp qword [out_size], msg_len
    jne .fail
    cmp qword [out_addr], 0
    je .fail

    ; ---- 4: byte-by-byte match against msg ----
    mov byte [fail_id], '4'
    mov r9, [out_addr]              ; mapped base
    lea r10, [msg]                  ; reference
    xor rcx, rcx
.cmp_loop:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, msg_len
    jb .cmp_loop

    ; ---- 5: munmap(addr, size) → 0 ----
    ; Caller owns the mapping and is responsible for the
    ; unmap. This sub-check exercises that contract.
    mov byte [fail_id], '5'
    mov rdi, [out_addr]
    mov rsi, [out_size]
    call munmap
    test rax, rax
    jnz .fail

    ; ---- 6: file_read_all on a missing path → -errno ----
    mov byte [fail_id], '6'
    ; Prime the out slots with sentinels the wrapper must
    ; NOT overwrite on failure. Values are kept within the
    ; signed-dword range so `mov qword [mem], imm32` does not
    ; trigger a NASM sign-extension warning.
    mov qword [out_addr], 0x11111111
    mov qword [out_size], 0x22222222
    lea rdi, [missing_path]
    lea rsi, [out_addr]
    lea rdx, [out_size]
    call file_read_all
    test rax, rax
    jns .fail                       ; want strictly negative

    ; ---- 7: empty file returns 0 / size=0 / addr=NULL ----
    mov byte [fail_id], '7'
    ; Clear the out slots first.
    mov qword [out_addr], -1        ; sentinel; must become NULL
    mov qword [out_size], -1        ; sentinel; must become 0
    lea rdi, [empty_src_path]
    lea rsi, [out_addr]
    lea rdx, [out_size]
    call file_read_all
    test rax, rax
    jnz .fail
    cmp qword [out_size], 0
    jne .fail
    cmp qword [out_addr], 0
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

.fail:
    lea rdi, [fail_msg]
    mov esi, fail_len
    call panic
    ; unreachable
