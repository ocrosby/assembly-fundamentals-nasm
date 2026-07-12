; atoi(s: rdi) -> i64
;
; Parses a decimal integer out of a NUL-terminated string.
; Semantics match C's `atoi`:
;
;   * Optional leading whitespace (space, tab, LF) is skipped.
;   * A single optional sign character (`+` or `-`) follows.
;   * Digits accumulate until the first non-digit byte.
;   * "No digits" (empty, all-whitespace, or a leading letter)
;     returns 0. `atoi("hello")` and `atoi("")` both give 0.
;   * No overflow check. Values above 2^63 - 1 wrap silently,
;     matching glibc's `atoi` behavior at optimized settings.
;
; Return value is a full 64-bit signed integer in rax; callers
; who want C's `int` can truncate the low 32 bits.

default rel

global atoi

section .text

atoi:
    xor eax, eax                    ; accumulator
    xor r8d, r8d                    ; sign flag: 0 = positive

.skip_ws:
    movzx ecx, byte [rdi]
    cmp cl, ' '
    je .skip_ws_step
    cmp cl, 9                       ; '\t'
    je .skip_ws_step
    cmp cl, 10                      ; '\n'
    jne .check_sign
.skip_ws_step:
    inc rdi
    jmp .skip_ws

.check_sign:
    cmp cl, '-'
    jne .check_plus
    mov r8d, 1
    inc rdi
    jmp .parse_digits
.check_plus:
    cmp cl, '+'
    jne .parse_digits
    inc rdi

.parse_digits:
    movzx ecx, byte [rdi]
    sub ecx, '0'
    cmp ecx, 9
    ja .apply_sign                  ; not a digit — done
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp .parse_digits

.apply_sign:
    test r8d, r8d
    jz .done
    neg rax
.done:
    ret
