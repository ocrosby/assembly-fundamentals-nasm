; buf_reserve(bufp, needed) -> 0 or -errno
;
; Ensure the buffer at `bufp` has capacity for at least `needed`
; bytes total. If it already does, this is a cheap no-op. If
; not, a new mapping is created, the existing `len` bytes are
; copied into it, and the old mapping is released.
;
; Arguments:
;   rdi = bufp
;   rsi = needed        minimum required capacity in bytes.
;
; Return:
;   rax = 0             capacity is now >= needed. On a grow,
;                       [bufp + BUF_DATA_OFF] is now the *new*
;                       address; any pointer the caller was
;                       holding into the old data region is
;                       invalidated. `len` is unchanged; the
;                       first `len` bytes carry over.
;   rax = -errno        the new mmap failed. `bufp` is left
;                       untouched — the old mapping is still
;                       live and callable.
;
; Grow strategy:
;   new_cap = max(cap * 2, needed) rounded up to BUF_PAGE_SIZE.
; Doubling gives amortized O(1) per byte appended; the
; page-granularity round-up matches the mmap unit.
;
; A failure at munmap of the old region after a successful new
; mmap is swallowed: the buffer is already in its new state and
; the caller cannot distinguish "grew, and old-region cleanup
; leaked" from "grew, and cleanup succeeded" with a return code
; without confusing the success/failure meaning. The leak, if
; it happens at all, is at most one prior-generation region.

%include "buf.inc"

default rel

extern mmap, munmap
global buf_reserve

section .text

buf_reserve:
    mov  rax, [rdi + BUF_CAP_OFF]
    cmp  rax, rsi
    jb   .grow                        ; cap < needed → must grow
    xor  eax, eax
    ret

.grow:
    push rbx
    push r12
    mov  rbx, rdi                     ; save bufp

    ; rax = old cap, rsi = needed. Compute new_cap = max(cap*2, needed).
    add  rax, rax
    cmp  rax, rsi
    jae  .have_new
    mov  rax, rsi
.have_new:
    ; Round up to page boundary.
    lea  rax, [rax + BUF_PAGE_SIZE - 1]
    and  rax, -BUF_PAGE_SIZE
    mov  r12, rax                     ; r12 = new_cap

    ; mmap(NULL, new_cap, PROT_R|W, MAP_PRIVATE|MAP_ANON, -1, 0)
    xor  edi, edi
    mov  rsi, r12
    mov  edx, BUF_PROT_READ_WRITE
    mov  ecx, BUF_MAP_FLAGS
    mov  r8, -1
    xor  r9d, r9d
    call mmap
    test rax, rax
    js   .out                         ; -errno — leave bufp untouched

    ; rax = new_data. Copy the first `len` bytes over.
    ; rep movsb: rdi=dst, rsi=src, rcx=count. All caller-saved.
    mov  rdi, rax
    mov  rsi, [rbx + BUF_DATA_OFF]
    mov  rcx, [rbx + BUF_LEN_OFF]
    push rax                          ; save new_data for the struct write
    push rsi                          ; save old_data for the munmap
    cld
    rep  movsb
    pop  rdi                          ; old_data → munmap.addr
    mov  rsi, [rbx + BUF_CAP_OFF]     ; old_cap → munmap.length
    call munmap                        ; ignore result (see header)

    pop  rax                          ; restore new_data
    mov  [rbx + BUF_DATA_OFF], rax
    mov  [rbx + BUF_CAP_OFF], r12
    xor  eax, eax
.out:
    pop  r12
    pop  rbx
    ret
