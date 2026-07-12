; buf_free(bufp) -> 0 or -errno
;
; Release the mmap region backing `bufp` and zero the three
; struct fields. Safe on a buffer whose data pointer is already
; NULL (e.g., a struct in .bss that was never init'd, or one
; that was freed once already) — no syscall runs in that case
; and rax returns 0.
;
; Arguments:
;   rdi = bufp
;
; Return:
;   rax = 0        success (mapping released, fields zeroed).
;   rax = -errno   munmap failed. The struct fields are still
;                  zeroed — libbuf treats a partial-release as
;                  end-of-life for the buffer, so the caller
;                  cannot accidentally reuse the stale pointer.
;                  The bytes the kernel refused to release are
;                  leaked; there is no retry path.
;
; End-of-life pairing: every buf_init must be matched by a
; buf_free before the containing scope exits, or the mapping
; leaks. buf_reset does not free — it only rewinds len.

%include "buf.inc"

default rel

extern munmap
global buf_free

section .text

buf_free:
    push rbx
    mov  rbx, rdi
    mov  rdi, [rbx + BUF_DATA_OFF]
    test rdi, rdi
    jz   .no_call                     ; data == 0: nothing to release
    mov  rsi, [rbx + BUF_CAP_OFF]
    call munmap                        ; rax = 0 or -errno; passthrough
    jmp  .zero
.no_call:
    xor  eax, eax
.zero:
    ; Zero the fields on both paths — even a failed munmap ends
    ; the buffer's life (see comment header).
    mov  qword [rbx + BUF_DATA_OFF], 0
    mov  qword [rbx + BUF_LEN_OFF],  0
    mov  qword [rbx + BUF_CAP_OFF],  0
    pop  rbx
    ret
