; inet_ntop4(src: rdi, dst: rsi, size: rdx) -> rax = dst or NULL
;
; Formats a u32 IPv4 address (already in network byte order) as
; dotted-decimal into `dst`. Byte 0 of the source u32 becomes
; the first octet; that mirrors what inet_pton4() writes, so
; round-tripping through both preserves the original text.
;
; POSIX inet_ntop() requires `size` to be at least
; INET_ADDRSTRLEN (16 bytes: "255.255.255.255" plus NUL). This
; wrapper enforces the same lower bound and returns NULL when
; the buffer is smaller. On success it returns the original
; `dst` pointer and NUL-terminates the output.
;
; No syscalls, no allocations. Uses div for the byte-to-decimal
; step; the conversion runs at most four times per call.

%include "syscall.inc"

; Emit the decimal representation of al (0..255) into [r13] and
; advance r13 past the written digits. Uses %%-scoped local
; labels so it can expand once per octet without conflict.
%macro EMIT_BYTE 0
    movzx eax, al
    cmp eax, 100
    jb %%maybe_two

    ; 100..255: hundreds, tens, ones.
    mov ecx, 100
    xor edx, edx
    div ecx                         ; eax = hundreds, edx = 0..99
    add al, '0'
    mov [r13], al
    inc r13
    mov eax, edx
    jmp %%two_digits

%%maybe_two:
    cmp eax, 10
    jb %%one_digit

%%two_digits:
    ; 10..99: tens, ones.
    mov ecx, 10
    xor edx, edx
    div ecx                         ; eax = tens, edx = ones
    add al, '0'
    mov [r13], al
    inc r13
    add dl, '0'
    mov [r13], dl
    inc r13
    jmp %%done

%%one_digit:
    add al, '0'
    mov [r13], al
    inc r13

%%done:
%endmacro

default rel

global inet_ntop4

section .text

inet_ntop4:
    cmp rdx, 16
    jb .too_small

    push r12                        ; src bytes shift out one at a time
    push r13                        ; dst walker

    mov r12, rdi
    mov r13, rsi

    ; Octet 0.
    mov al, r12b
    EMIT_BYTE
    mov byte [r13], '.'
    inc r13

    ; Octet 1.
    shr r12, 8
    mov al, r12b
    EMIT_BYTE
    mov byte [r13], '.'
    inc r13

    ; Octet 2.
    shr r12, 8
    mov al, r12b
    EMIT_BYTE
    mov byte [r13], '.'
    inc r13

    ; Octet 3.
    shr r12, 8
    mov al, r12b
    EMIT_BYTE
    mov byte [r13], 0

    mov rax, rsi                    ; return original dst
    pop r13
    pop r12
    ret

.too_small:
    xor eax, eax                    ; NULL
    ret
