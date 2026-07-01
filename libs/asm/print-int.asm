; print_int(n: rdi)
;
; Formats a signed 64-bit integer as decimal and writes it to
; stdout via sys_write. Handles negatives, including LLONG_MIN
; (whose absolute value exists only as an unsigned 64-bit
; quantity — see the `neg` step below).
;
; Algorithm: divide-by-10 into a stack buffer, filling backwards
; from the tail. When the quotient hits zero, rsi points at the
; first digit; sys_write from there to the end of the buffer.

%ifdef MACOS
%define SYS_WRITE 0x2000004         ; BSD class 2, call 4
%else
%define SYS_WRITE 1                 ; Linux write(2)
%endif

default rel

global print_int

section .text

print_int:
    ; A 20-digit i64 plus an optional '-' fits in 21 bytes.
    ; Rounded up to 32 so 21 bytes of buffer sit inside a single
    ; aligned scratch region on the stack.
    sub rsp, 32                     ; scratch buffer

    ; Build the string backwards. rsi walks left, one byte per digit.
    lea rsi, [rsp + 32]             ; one past the last buffer byte

    xor r8d, r8d                    ; r8b = "was negative" flag
    mov rax, rdi                    ; working value
    test rax, rax
    jns .to_digits                  ; already non-negative
    mov r8b, 1                      ; remember the sign
    neg rax                         ; abs; for LLONG_MIN this yields
                                    ; 0x8000000000000000 which is
                                    ; exactly |LLONG_MIN| unsigned.

.to_digits:
    mov rcx, 10                     ; divisor
.next_digit:
    xor rdx, rdx                    ; clear high half of dividend
    div rcx                         ; rax /= 10, rdx = rax % 10
    add dl, '0'                     ; digit -> ASCII
    dec rsi                         ; back up one byte
    mov [rsi], dl                   ; store digit
    test rax, rax
    jnz .next_digit                 ; loop while quotient > 0

    test r8b, r8b
    jz .write                       ; positive: no sign to prepend
    dec rsi
    mov byte [rsi], '-'             ; prepend '-'

.write:
    lea rdx, [rsp + 32]             ; end of buffer
    sub rdx, rsi                    ; len = end - start
    mov rdi, 1                      ; arg 1: fd = stdout
                                    ; arg 2: buf already in rsi
    mov rax, SYS_WRITE
    syscall                         ; sys_write(1, buf, len)

    add rsp, 32
    ret
