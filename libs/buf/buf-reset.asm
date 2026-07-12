; buf_reset(bufp) -> void
;
; Rewind the buffer to empty without releasing the mapping.
; Sets `len` to 0 and leaves `data` and `cap` intact — the
; caller can immediately append again into the same mapping.
;
; Arguments:
;   rdi = bufp
;
; Return: none. rax is not written; the callee-saved contract
; is preserved because this routine touches only memory.
;
; This exists as a named symbol (rather than an inline
; `mov qword [bufp + BUF_LEN_OFF], 0`) so that the intent —
; "reuse the buffer for the next request" — is legible at the
; call site. Cheap alternative to buf_free + buf_init when
; churning through multiple messages on one connection.

%include "buf.inc"

default rel

global buf_reset

section .text

buf_reset:
    mov  qword [rdi + BUF_LEN_OFF], 0
    ret
