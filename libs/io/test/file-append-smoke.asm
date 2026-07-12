; file-append-smoke.asm — v1.14 file_append round-trip.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; calls libasm's `panic` with "FAIL:<id>\n" and exits
; 1 otherwise. run.sh passes -DDST_PATH and -DBAD_PATH via
; mktemp'd names / a known-missing directory.
;
; Sub-check ids:
;
;   1  file_append(DST, "HELLO ", 6) into a fresh path (file
;      created) returns 0.
;   2  file_append(DST, "WORLD!", 6) into the same path
;      returns 0; the file must now contain "HELLO WORLD!".
;   3  Read the file back and byte-compare against
;      "HELLO WORLD!". Confirms append semantics — the second
;      call did NOT truncate.
;   4  io_size(DST) reports 12 — proves the file grew rather
;      than shrinking.
;   5  file_append(BAD_PATH, msg, len) on a path whose
;      parent directory does not exist returns negative errno.
;   6  file_append(EMPTY_PATH, addr, 0) on a fresh path
;      returns 0 and produces an empty file (io_size == 0).

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
%define DST_PATH "/tmp/libio-file-append-smoke.dst"
%endif
%ifndef EMPTY_PATH
%define EMPTY_PATH "/tmp/libio-file-append-smoke.empty"
%endif
%ifndef BAD_PATH
%define BAD_PATH "/proc/libio/does-not-exist-fap/child"
%endif

default rel

extern open, io_size, file_append
extern panic                        ; libasm

global _start
global _main

section .rodata
dst_path:   db DST_PATH, 0
empty_path: db EMPTY_PATH, 0
bad_path:   db BAD_PATH, 0

part_a:   db "HELLO "
part_a_len: equ $ - part_a          ; 6
part_b:   db "WORLD!"
part_b_len: equ $ - part_b          ; 6
expected: db "HELLO WORLD!"
expected_len: equ $ - expected      ; 12

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
    ; ---- 1: file_append(DST, "HELLO ", 6) — fresh file ----
    ; run.sh mktemp'd DST_PATH but did not create the file.
    ; This sub-check exercises the "create on demand"
    ; branch of O_CREAT.
    mov byte [fail_id], '1'
    lea rdi, [dst_path]
    lea rsi, [part_a]
    mov rdx, part_a_len
    call file_append
    test rax, rax
    jnz .fail

    ; ---- 2: file_append(DST, "WORLD!", 6) — extend ----
    mov byte [fail_id], '2'
    lea rdi, [dst_path]
    lea rsi, [part_b]
    mov rdx, part_b_len
    call file_append
    test rax, rax
    jnz .fail

    ; ---- 3: read back and byte-compare vs "HELLO WORLD!" ----
    mov byte [fail_id], '3'
    lea rdi, [dst_path]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .fail
    mov ebx, eax                    ; fd

    mov edi, ebx
    lea rsi, [buf16]
    mov edx, expected_len
    mov rax, SYS_read
    syscall
%ifdef MACOS
    jnc .read_ok
    neg rax
.read_ok:
%endif
    cmp rax, expected_len
    jne .fail

    lea r9, [buf16]
    lea r10, [expected]
    xor rcx, rcx
.cmp_loop:
    mov al, [r9 + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, expected_len
    jb .cmp_loop

    ; ---- 4: io_size reports 12 — file grew, no truncate ----
    mov byte [fail_id], '4'
    mov edi, ebx
    lea rsi, [size_out]
    call io_size
    test rax, rax
    jnz .fail
    cmp qword [size_out], expected_len
    jne .fail

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; ---- 5: bad path (missing parent) → negative errno ----
    mov byte [fail_id], '5'
    lea rdi, [bad_path]
    lea rsi, [part_a]
    mov rdx, part_a_len
    call file_append
    test rax, rax
    jns .fail                       ; want strictly negative

    ; ---- 6: size = 0 on a fresh path → empty file ----
    mov byte [fail_id], '6'
    lea rdi, [empty_path]
    lea rsi, [part_a]               ; addr irrelevant when size=0
    xor rdx, rdx
    call file_append
    test rax, rax
    jnz .fail

    lea rdi, [empty_path]
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
