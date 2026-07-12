; iov-smoke.asm — v1.10 readv + writev round trip through a pipe.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; prints "FAIL:<id>\n" to stderr and exits 1 otherwise.
;
; Sub-check ids:
;
;   1  pipe(pipefd) → 0
;   2  writev(pipefd[1], iov_out, 3) → 12 bytes (4+4+4)
;   3  readv(pipefd[0], iov_in, 2)  → 12 bytes filled across two 6-byte iovecs
;   4  buf_in_a == "HELLOWO"   (first 6 bytes: "HELLOW" — wait actually "HELLOW"[6]?
;      no: writev sends "HELL" + "O WO" + "RLD!" = 12 bytes; the first
;      6 bytes are "HELLO ")
;   5  buf_in_b == "WORLD!"
;
; The example demonstrates the interesting property of the
; iov* family: the *sender* and *receiver* do not have to
; agree on where the boundaries sit. writev sends three
; 4-byte chunks; readv fills two 6-byte chunks. The kernel
; treats both sides as a continuous byte stream and splits /
; joins accordingly.

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern readv, writev, pipe
extern panic                        ; libasm v1.1
extern memcmp                       ; libstr v1.0

global _start
global _main

section .rodata
; Three 4-byte chunks that spell "HELLO WORLD!" back-to-back.
part_a:  db "HELL"
part_b:  db "O WO"
part_c:  db "RLD!"

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

; Expected receive buffers for sub-checks 4 and 5. writev
; concatenates part_a + part_b + part_c = "HELLO WORLD!" as a
; stream. readv splits it across two 6-byte iovecs, so:
;   buf_in_a = "HELLO "   (bytes 0..5)
;   buf_in_b = "WORLD!"   (bytes 6..11)
;
; libstr's memcmp does the byte compare in one call. The prior
; version split each 6-byte compare into a dword + a word to
; avoid a byte loop; memcmp makes that mechanical split
; unnecessary and lets the intent read directly.
expected_a: db "HELLO "             ; 6 bytes, no NUL
expected_b: db "WORLD!"             ; 6 bytes, no NUL

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
pipefd:   resd 2
iov_out:  resb IOVEC_SIZE * 3       ; three 4-byte send chunks
iov_in:   resb IOVEC_SIZE * 2       ; two 6-byte recv chunks
buf_in_a: resb 6
buf_in_b: resb 6

section .text

_start:
_main:
    ; ---- 1: pipe(pipefd) → 0 ----
    mov byte [fail_id], '1'
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; ---- Build iov_out: three iovecs pointing at part_a, part_b, part_c ----
    lea rax, [part_a]
    mov [iov_out + 0*IOVEC_SIZE + IOV_BASE_OFF], rax
    mov qword [iov_out + 0*IOVEC_SIZE + IOV_LEN_OFF], 4

    lea rax, [part_b]
    mov [iov_out + 1*IOVEC_SIZE + IOV_BASE_OFF], rax
    mov qword [iov_out + 1*IOVEC_SIZE + IOV_LEN_OFF], 4

    lea rax, [part_c]
    mov [iov_out + 2*IOVEC_SIZE + IOV_BASE_OFF], rax
    mov qword [iov_out + 2*IOVEC_SIZE + IOV_LEN_OFF], 4

    ; ---- 2: writev(pipefd[1], iov_out, 3) → 12 ----
    mov byte [fail_id], '2'
    mov edi, [pipefd + 4]
    lea rsi, [iov_out]
    mov edx, 3
    call writev
    cmp rax, 12
    jne .fail

    ; ---- Build iov_in: two iovecs pointing at buf_in_a, buf_in_b, 6 bytes each ----
    lea rax, [buf_in_a]
    mov [iov_in + 0*IOVEC_SIZE + IOV_BASE_OFF], rax
    mov qword [iov_in + 0*IOVEC_SIZE + IOV_LEN_OFF], 6

    lea rax, [buf_in_b]
    mov [iov_in + 1*IOVEC_SIZE + IOV_BASE_OFF], rax
    mov qword [iov_in + 1*IOVEC_SIZE + IOV_LEN_OFF], 6

    ; ---- 3: readv(pipefd[0], iov_in, 2) → 12 ----
    mov byte [fail_id], '3'
    mov edi, [pipefd]
    lea rsi, [iov_in]
    mov edx, 2
    call readv
    cmp rax, 12
    jne .fail

    ; ---- 4: buf_in_a == "HELLO " ----
    mov byte [fail_id], '4'
    lea rdi, [buf_in_a]
    lea rsi, [expected_a]
    mov edx, 6
    call memcmp
    test rax, rax
    jnz .fail

    ; ---- 5: buf_in_b == "WORLD!" ----
    mov byte [fail_id], '5'
    lea rdi, [buf_in_b]
    lea rsi, [expected_b]
    mov edx, 6
    call memcmp
    test rax, rax
    jnz .fail

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
    ; libasm v1.1's panic writes to stderr and exits(1). The
    ; fail_id byte was patched by whichever sub-check failed,
    ; so fail_msg still starts with "FAIL:<id>".
    lea rdi, [fail_msg]
    mov esi, fail_len
    call panic
    ; unreachable
