; http_parse_request_line(buf, len, out) -> bytes_consumed or -errno
;
; Parse an HTTP/1.x request line per RFC 9112 §3:
;
;     request-line = method SP request-target SP HTTP-version CRLF
;
; from `buf[0..len)` into the caller-supplied `struct
; http_request_line` at `out` (see http.inc for the layout).
;
; Arguments:
;   rdi = buf         u8 pointer to the input bytes
;   rsi = len         u64 count of readable bytes at buf
;   rdx = out         pointer to a REQUEST_LINE_SIZE-byte struct
;
; Return in rax:
;   > 0            bytes consumed, up through and including the
;                  terminating CRLF. Everything before this
;                  offset can be reclaimed by the caller.
;   -HTTP_EAGAIN   the input does not yet contain a full request
;                  line — the caller reads more bytes and retries
;                  from the same offset.
;   -HTTP_EINVAL   the input contains a definitely-malformed
;                  line (bad HTTP-version literal, non-CRLF at
;                  the end of the version, request-target that
;                  starts with a control character, etc.). The
;                  caller closes the connection or replies
;                  400 Bad Request.
;
; The out struct fields are written *only* on the success path.
; Both error returns leave `out` untouched.
;
; What this routine does NOT do:
;
; - It does not validate the method token character set. Any
;   sequence of non-SP, non-CTL bytes before the first SP is
;   accepted as the method; the caller compares it against a
;   known list. RFC 9110 §5.6.2 defines token, but a permissive
;   parser here defers the validation to the point where it
;   actually matters (the dispatcher).
; - It does not validate the request-target scheme or path.
;   Any sequence of non-SP bytes between the two SPs is
;   accepted; RFC 9112 §3.2's four target forms are for a
;   later URL parser.
; - It does not tolerate obs-fold whitespace anywhere in the
;   line. RFC 9112 §5 permits obs-fold only inside header
;   values, not on the start-line.

%include "http.inc"

default rel

extern memchr                       ; libstr

global http_parse_request_line

section .rodata
http_prefix: db "HTTP/1."           ; 7 bytes; version digit follows

section .text

http_parse_request_line:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov  rbx, rdi                    ; rbx = buf
    mov  r12, rsi                    ; r12 = len
    mov  r13, rdx                    ; r13 = out struct

    ; ---- Find the first SP: end of the method token --------
    ; memchr(buf, ' ', len). NULL → -EAGAIN (not enough input).
    mov  rdi, rbx
    mov  esi, ' '
    mov  rdx, r12
    call memchr
    test rax, rax
    jz   .need_more                  ; no SP yet
    ; Reject a zero-length method (line starts with SP).
    cmp  rax, rbx
    je   .malformed
    mov  r14, rax                    ; r14 = pointer to first SP

    ; ---- Find the second SP: end of the request-target -----
    ; Start scan just past the first SP.
    lea  rdi, [r14 + 1]
    mov  rax, rbx
    add  rax, r12
    mov  rdx, rax
    sub  rdx, rdi                    ; rdx = bytes remaining
    test rdx, rdx
    jle  .need_more
    mov  esi, ' '
    call memchr
    test rax, rax
    jz   .need_more
    ; Reject a zero-length request-target (two SPs in a row).
    lea  rcx, [r14 + 1]
    cmp  rax, rcx
    je   .malformed
    mov  r15, rax                    ; r15 = pointer to second SP

    ; ---- Verify HTTP-version + CRLF ------------------------
    ; Layout after the second SP:
    ;   +0 .. +6  "HTTP/1."
    ;   +7        '0' or '1'
    ;   +8        '\r'
    ;   +9        '\n'
    ; Total 10 bytes past the second SP; +1 for the SP itself,
    ; so the caller must have (second_sp_offset + 1 + 10) bytes
    ; before we can decide. Fewer → need more input.
    lea  rdi, [r15 + 1]              ; rdi = ptr to HTTP-version start
    mov  rax, rbx
    add  rax, r12                    ; rax = end of buf
    sub  rax, rdi                    ; rax = bytes at rdi and beyond
    cmp  rax, 10
    jl   .need_more

    ; Compare the 7-byte "HTTP/1." literal.
    lea  rsi, [rel http_prefix]
    mov  rcx, 7
    cld
    repe cmpsb
    jne  .malformed                  ; wrong literal

    ; Minor version digit at [r15 + 8]. Fast path checks '0' /
    ; '1'; anything else is rejected. RFC 9112 §2.5 says
    ; unrecognized minor versions on HTTP/1 should be treated
    ; per the highest 1.x the recipient understands — but for
    ; a fresh implementation that only supports 1.0 and 1.1,
    ; a hard reject is honest.
    movzx eax, byte [r15 + 8]
    cmp  al, '0'
    je   .v10
    cmp  al, '1'
    jne  .malformed
    mov  ecx, HTTP_VERSION_11
    jmp  .have_version
.v10:
    mov  ecx, HTTP_VERSION_10
.have_version:
    ; CRLF check.
    cmp  word [r15 + 9], 0x0A0D       ; little-endian CR then LF
    jne  .malformed

    ; ---- Success — fill out the struct ---------------------
    ; method_ptr = buf; method_len = r14 - buf
    mov  [r13 + RL_METHOD_PTR_OFF], rbx
    mov  rax, r14
    sub  rax, rbx
    mov  [r13 + RL_METHOD_LEN_OFF], rax

    ; target_ptr = r14 + 1; target_len = r15 - (r14 + 1)
    lea  rax, [r14 + 1]
    mov  [r13 + RL_TARGET_PTR_OFF], rax
    mov  rax, r15
    sub  rax, r14
    dec  rax                          ; r15 - r14 - 1
    mov  [r13 + RL_TARGET_LEN_OFF], rax

    mov  [r13 + RL_VERSION_OFF], ecx

    ; bytes_consumed = (r15 + 1 + 10) - buf
    lea  rax, [r15 + 11]
    sub  rax, rbx
    jmp  .out

.need_more:
    mov  rax, -HTTP_EAGAIN
    jmp  .out

.malformed:
    mov  rax, -HTTP_EINVAL
.out:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    ret
