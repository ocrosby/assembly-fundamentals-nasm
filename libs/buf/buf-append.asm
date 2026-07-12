; buf_append(bufp, src, n) -> 0 or -errno
;
; Copy `n` bytes from `src` into the buffer at position `len`,
; growing the mapping if the current capacity does not fit
; `len + n`. On success, `len` advances by `n`.
;
; Arguments:
;   rdi = bufp
;   rsi = src           source byte pointer.
;   rdx = n             byte count. Zero is legal (no-op).
;
; Return:
;   rax = 0             bytes copied, len updated.
;   rax = -errno        the internal buf_reserve grow failed;
;                       len and data are unchanged.
;
; A grow may relocate the mapping — any pointer a caller was
; holding into the buffer is invalidated after this call. Read
; through [bufp + BUF_DATA_OFF] fresh each time.
;
; The len + n sum is *not* checked for 64-bit overflow: reaching
; a 2**64-byte buffer would require an mmap the kernel would
; refuse long before the pointer arithmetic wrapped, and the
; refusal surfaces as -ENOMEM from buf_reserve.

%include "buf.inc"

default rel

extern buf_reserve
global buf_append

section .text

buf_append:
    push rbx
    push r12
    push r13
    mov  rbx, rdi                     ; bufp
    mov  r12, rsi                     ; src
    mov  r13, rdx                     ; n

    ; buf_reserve(bufp, len + n)
    mov  rdi, rbx
    mov  rsi, [rbx + BUF_LEN_OFF]
    add  rsi, r13
    call buf_reserve
    test rax, rax
    js   .out                         ; -errno passthrough

    ; memcpy(data + len, src, n) via rep movsb.
    mov  rdi, [rbx + BUF_DATA_OFF]
    add  rdi, [rbx + BUF_LEN_OFF]
    mov  rsi, r12
    mov  rcx, r13
    cld
    rep  movsb

    add  [rbx + BUF_LEN_OFF], r13
    xor  eax, eax
.out:
    pop  r13
    pop  r12
    pop  rbx
    ret
