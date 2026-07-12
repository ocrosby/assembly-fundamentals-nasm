; Slurp standard input into a growable byte buffer, then write
; the whole accumulated content back to standard output in a
; single `sys_write` call. Exit 42 on success (buffer freed
; cleanly), 1 on any syscall or libbuf error.
;
; Introduces libbuf: the first example that uses the `libbuf.a`
; archive introduced in the same commit range. Every earlier
; read/echo example (from 08-echo-loop onward) wrote one chunk
; per chunk read — the loop was symmetric because the buffer
; size was fixed. This example is asymmetric: reads stay
; chunked (128 bytes at a time), but the write side is one
; large syscall over the full accumulated content. That is only
; possible because libbuf grew the mapping as bytes arrived.
;
; What the buffer does under the hood:
;
;   buf_init(&b, 0)                → mmap one page (4096 bytes)
;   buf_append(&b, chunk, n)       → memcpy into [data+len],
;                                    growing via
;                                    mmap-new / memcpy /
;                                    munmap-old if len + n > cap
;   buf_free(&b)                   → munmap and zero the struct
;
; A grow can relocate the mapping — the write below rereads
; `[b + BUF_DATA_OFF]` after the read loop finishes, so any
; grows that happened along the way are already accounted for.
;
; With an empty stdin, the read loop hits EOF immediately, the
; write is a zero-byte syscall, and the buffer is freed with no
; grow ever needed. CI drives this path (see the pipe_stdin
; entry in .github/workflows/ci.yml).

%ifdef MACOS
%define SYS_READ  0x2000003
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_READ  0
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

; Struct offsets from libs/buf/buf.inc — inlined here to keep
; the example self-contained (no `-I ../../libs/buf` on the
; nasm command line, matching the pattern of every other
; example in this repo).
%define BUF_SIZE       24
%define BUF_DATA_OFF    0
%define BUF_LEN_OFF     8

CHUNK_SIZE equ 128

default rel

extern buf_init, buf_append, buf_free

global _start
global _main

section .text

_start:
_main:
    ; buf_init(&b, 0) — the zero-cap form rounds up to one
    ; page. That covers a typical shell prompt of input
    ; without ever growing.
    lea  rdi, [b]
    xor  esi, esi
    call buf_init
    test rax, rax
    js   .fail

.read_loop:
    ; sys_read(0, chunk, CHUNK_SIZE) → rax bytes read.
    mov  rax, SYS_READ
    xor  edi, edi                     ; fd = stdin
    lea  rsi, [chunk]
    mov  edx, CHUNK_SIZE
    syscall
    test rax, rax
    jz   .flush                       ; rax == 0 → EOF
    js   .fail                        ; rax  < 0 → -errno

    ; buf_append(&b, chunk, rax) — grow may relocate data.
    mov  rdx, rax                     ; n = bytes just read
    lea  rdi, [b]
    lea  rsi, [chunk]
    call buf_append
    test rax, rax
    js   .fail
    jmp  .read_loop

.flush:
    ; sys_write(1, b.data, b.len) — one syscall over the full
    ; accumulated content. Reread b.data *after* the read loop
    ; because an intervening buf_append may have relocated the
    ; mapping.
    mov  rax, SYS_WRITE
    mov  edi, 1                       ; fd = stdout
    mov  rsi, [b + BUF_DATA_OFF]
    mov  rdx, [b + BUF_LEN_OFF]
    syscall
    test rax, rax
    js   .fail

    ; buf_free(&b) — munmap the region and zero the struct.
    lea  rdi, [b]
    call buf_free
    test rax, rax
    js   .fail

    ; exit(42) — the standard "libbuf/libio series" success
    ; sentinel matched by CI's expected map.
    mov  rax, SYS_EXIT
    mov  edi, 42
    syscall

.fail:
    mov  rax, SYS_EXIT
    mov  edi, 1
    syscall

section .bss
b:     resb BUF_SIZE
chunk: resb CHUNK_SIZE
