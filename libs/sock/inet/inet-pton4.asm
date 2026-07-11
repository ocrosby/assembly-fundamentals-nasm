; inet_pton4(src: rdi, dst: rsi) -> rax = 1 on success, 0 on failure
;
; Parses a NUL-terminated dotted-decimal IPv4 address like
; "192.168.1.1" and writes the four octets to *dst in network
; byte order (the first octet of the string goes to dst[0], so
; the resulting u32 read from *dst is already in network order).
;
; The parse is strict, matching POSIX inet_pton() for AF_INET:
;
;   * Each octet must be one to three decimal digits.
;   * A leading '0' is only accepted when the whole octet is "0"
;     — "01" is rejected. This avoids the historical trap where
;     "0177" is read as octal by inet_aton() but as decimal 177
;     by inet_pton().
;   * Each octet must be in the range 0..255.
;   * Exactly three dots must separate four octets, with a NUL
;     terminating the string.
;
; No allocations, no syscalls. All work happens in registers and
; a five-slot push/pop frame.

default rel

global inet_pton4

section .text

inet_pton4:
    push rbx                        ; octet counter (4..1, decremented)
    push r12                        ; src walker
    push r13                        ; dst walker

    mov r12, rdi
    mov r13, rsi
    mov ebx, 4                      ; four octets to consume

.next_octet:
    ; Look at the first digit of the octet.
    movzx ecx, byte [r12]
    sub ecx, '0'
    cmp ecx, 9
    ja .fail                        ; must have at least one digit
    inc r12

    test ecx, ecx
    jnz .accum                      ; nonzero first digit → normal path

    ; First digit is '0': the whole octet must be exactly "0".
    ; If the next byte is another digit, this is a leading zero.
    movzx eax, byte [r12]
    sub eax, '0'
    cmp eax, 9
    jbe .fail                       ; more digits after leading '0'
    xor eax, eax                    ; octet value = 0
    jmp .store

.accum:
    mov eax, ecx                    ; eax = value so far
.accum_loop:
    movzx ecx, byte [r12]
    sub ecx, '0'
    cmp ecx, 9
    ja .store                       ; non-digit ends the octet
    lea eax, [eax + eax*4]          ; eax *= 5
    lea eax, [ecx + eax*2]          ; eax = eax*10 + digit
    cmp eax, 255
    ja .fail                        ; octet out of range
    inc r12
    jmp .accum_loop

.store:
    mov [r13], al                   ; write octet
    inc r13
    dec ebx
    jz .expect_nul                  ; wrote the fourth octet

    ; Expect '.' between octets.
    movzx ecx, byte [r12]
    cmp ecx, '.'
    jne .fail
    inc r12
    jmp .next_octet

.expect_nul:
    movzx ecx, byte [r12]
    test ecx, ecx
    jnz .fail                       ; trailing garbage after "a.b.c.d"
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r13
    pop r12
    pop rbx
    ret
