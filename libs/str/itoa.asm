; itoa(n: rdi, buf: rsi) -> bytes_written
;
; Formats the signed 64-bit integer `n` as decimal into `buf`
; and returns the number of bytes written. Does NOT write a
; trailing NUL — the caller is responsible for that if the
; output feeds a NUL-terminated consumer. This matches
; `print_int`'s "just the digits" contract (see
; [`libs/asm/print-int.asm`](../asm/print-int.asm)) so the
; two can share downstream code paths.
;
; The maximum output length is 20 bytes:
;
;   * `0`                    → 1 byte
;   * `9223372036854775807`  → 19 bytes (LLONG_MAX)
;   * `-9223372036854775808` → 20 bytes (LLONG_MIN)
;
; Callers reserving `resb 20` in .bss get a portable output
; buffer. LLONG_MIN is handled correctly: `neg` on the
; sign-only bit pattern leaves rax as the unsigned quantity
; `2^63`, and `div` is unsigned, so the divide loop produces
; the right digits without a special case.
;
; The algorithm writes digits backwards into a stack scratch,
; then copies the accumulated run forward into `buf`. This is
; simpler than a two-pass approach (count digits, then write
; forward) and keeps the whole routine leaf-local (no calls
; into the archive).

default rel

global itoa

section .text

itoa:
    ; sub rsp, 24 gives us a 24-byte scratch — 20 digits + '-'
    ; + slack. Entry rsp % 16 == 8; after sub rsp, 24 the
    ; alignment is (8 - 24) mod 16 = 0. No calls happen in
    ; the body, so alignment is only relevant for the epilog.
    sub rsp, 24

    ; Preserve caller-provided pointers across the div loop.
    ; r10 = original n; r11 = destination buffer base.
    mov r10, rdi
    mov r11, rsi

    ; Working value in rax. If negative, remember and negate.
    mov rax, r10
    xor ecx, ecx                    ; sign flag: 0 = positive
    test rax, rax
    jns .to_digits
    mov ecx, 1
    neg rax                         ; LLONG_MIN self-negates to
                                    ; its unsigned magnitude

.to_digits:
    ; Walk backwards from the end of the scratch, one byte
    ; per digit.
    lea r9, [rsp + 24]              ; one past last scratch byte
    mov r8, 10                      ; divisor
.next_digit:
    xor edx, edx
    div r8                          ; rax = rax / 10, rdx = rax % 10
    add dl, '0'
    dec r9
    mov [r9], dl
    test rax, rax
    jnz .next_digit

    ; Prepend '-' if the original value was negative.
    test ecx, ecx
    jz .copy
    dec r9
    mov byte [r9], '-'

.copy:
    ; length = end_of_scratch - r9
    lea rax, [rsp + 24]
    sub rax, r9                     ; total bytes written
    ; Copy the digit run into the caller's buffer.
    mov rdi, r11                    ; dst
    mov rsi, r9                     ; src
    mov rcx, rax
    ; rep movsb overwrites rax, so stash the length across
    ; the copy and restore it as the return value.
    push rax
    rep movsb
    pop rax

    add rsp, 24
    ret
