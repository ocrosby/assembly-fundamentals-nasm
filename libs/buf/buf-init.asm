; buf_init(bufp, initial_cap) -> 0 or -errno
;
; Establish a fresh growable byte buffer at `bufp`. The caller
; supplies the 24-byte struct (in `.bss` via `resb BUF_SIZE` or
; on the stack); this routine fills in the fields and mmap's
; the initial data region.
;
; Arguments:
;   rdi = bufp         pointer to a BUF_SIZE-byte struct.
;   rsi = initial_cap  requested capacity in bytes; rounded up
;                      to BUF_PAGE_SIZE (4096). Zero is legal
;                      and produces a one-page mapping.
;
; Return:
;   rax = 0            success. bufp fields are written:
;                        [bufp + BUF_DATA_OFF] = mapping address
;                        [bufp + BUF_LEN_OFF]  = 0
;                        [bufp + BUF_CAP_OFF]  = rounded-up cap
;   rax = -errno       mmap failed; bufp is left untouched.
;
; Consumers that reuse a struct across multiple buffer lifetimes
; must call buf_free between buf_init calls — otherwise the
; earlier mapping leaks.

%include "buf.inc"

default rel

extern mmap
global buf_init

section .text

buf_init:
    push rbx                          ; preserve bufp across mmap
    mov  rbx, rdi

    ; Round rsi up to a page boundary. Zero → one page.
    lea  rsi, [rsi + BUF_PAGE_SIZE - 1]
    and  rsi, -BUF_PAGE_SIZE
    test rsi, rsi
    jnz  .have_size
    mov  esi, BUF_PAGE_SIZE
.have_size:
    push rsi                          ; stash rounded cap for the write-back

    ; mmap(NULL, cap, PROT_R|W, MAP_PRIVATE|MAP_ANON, -1, 0)
    xor  edi, edi                     ; addr = NULL
    mov  edx, BUF_PROT_READ_WRITE
    mov  ecx, BUF_MAP_FLAGS
    mov  r8, -1                       ; fd = -1
    xor  r9d, r9d                     ; offset = 0
    call mmap

    pop  rcx                          ; recover rounded cap
    test rax, rax
    js   .out                         ; -errno; leave bufp untouched

    mov  [rbx + BUF_DATA_OFF], rax
    mov  qword [rbx + BUF_LEN_OFF], 0
    mov  [rbx + BUF_CAP_OFF], rcx
    xor  eax, eax
.out:
    pop  rbx
    ret
