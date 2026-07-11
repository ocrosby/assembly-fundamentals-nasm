; send_all(fd, buf, len) -> rax = 0 or -errno
;
; Loop through write() until all `len` bytes have been sent
; or an error occurs. Handles the "short write" case where
; the kernel wrote fewer bytes than requested by advancing
; the buffer pointer and shrinking the remaining count.
;
; Every socket example that "just" writes a small buffer
; (`cmp rax, msg_len; jne .fail`) is banking on the kernel
; being able to accept the whole thing at once — a fine
; assumption for tiny payloads on a fresh socket, and a bad
; assumption for anything larger. `send_all` factors the
; loop out so callers stop having to.
;
; Arguments:
;   rdi = fd       socket, pipe, or any writable fd
;   rsi = buf*     pointer to the bytes to send
;   rdx = len      bytes to send
;
; Return:
;   rax = 0        all `len` bytes were written
;   rax = -errno   first errno from write() propagated
;                  as-is. -EIO is returned as a sentinel if
;                  write() ever returns 0 with more bytes
;                  left to send (an "impossible" state on
;                  blocking sockets that would otherwise
;                  loop forever).
;
; Signal-restart semantics: this helper does NOT retry on
; -EINTR. Callers that want SA_RESTART-style behavior wrap
; the call in their own retry.
;
; Register roles (all callee-saved so nested write() calls
; do not disturb the loop state):
;   r12 = fd
;   r13 = buf pointer, advances by the number of bytes each
;         write() actually accepted
;   r14 = remaining bytes to send

%include "syscall.inc"

default rel

extern write

global send_all

section .text

send_all:
    push r12
    push r13
    push r14

    mov r12d, edi                   ; fd
    mov r13, rsi                    ; buf
    mov r14, rdx                    ; remaining

.loop:
    test r14, r14
    jz .done_ok                     ; nothing left → success

    mov edi, r12d
    mov rsi, r13
    mov rdx, r14
    call write
    test rax, rax
    js .done_err                    ; -errno from kernel
    jz .zero_write                  ; short-of-progress guard

    add r13, rax                    ; advance buf
    sub r14, rax                    ; shrink remaining
    jmp .loop

.zero_write:
    ; write() returned 0 with bytes still to send. Blocking
    ; sockets should never do this; treat it as -EIO so the
    ; loop cannot spin forever.
    mov rax, -5

.done_err:
    pop r14
    pop r13
    pop r12
    ret

.done_ok:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    ret
