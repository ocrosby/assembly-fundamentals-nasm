; inet_ntop6(src: rdi, dst: rsi, size: rdx) -> rax = dst or NULL
;
; Formats a 16-byte IPv6 address (network byte order) into RFC 5952
; canonical text at *dst:
;
;   * Lowercase hex digits ('a'..'f', not 'A'..'F').
;   * No leading zeros inside a group (0x00ab → "ab", 0x0000 → "0").
;   * The longest run of two or more consecutive zero groups is
;     compressed to "::". When multiple runs tie for the longest,
;     the first run wins (RFC 5952 §4.2.3).
;   * At most one "::" per output.
;   * IPv4-mapped addresses (bytes 0..9 zero, bytes 10..11 = 0xFF)
;     are printed as "::ffff:a.b.c.d" instead of "::ffff:xxxx:yyyy".
;   * IPv4-compatible addresses (bytes 0..11 zero) still print as
;     hex — the RFC deprecates the ::a.b.c.d shorthand for that case.
;
; The destination buffer must be at least INET6_ADDRSTRLEN (46
; bytes: "ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255" plus NUL).
; Returns NULL if `size` is smaller. On success returns the
; original `dst`.

%include "syscall.inc"

default rel

global inet_ntop6

section .text

; Register roles across the function:
;   r12 = src pointer (16 bytes, kept for IPv4-tail byte access)
;   r13 = dst walker
;   [rsp..rsp+16] = 8 u16 host-order groups
;   ebx  = best_start (index where longest zero run begins)
;   r14d = best_len (length of the longest zero run, or 0)
;   r15d = "in v4 tail mode" flag (used inside .emit_hex path)
;   ecx  = current group index in the emit loop
;   r10d = "need separator" flag in the emit loop
;
; The .emit_group, .hex_char, and .emit_byte helpers are internal
; call/ret subroutines and preserve ecx / r10d / r14d / ebx / r12
; / r13 so the emit loop can rely on them.

inet_ntop6:
    cmp rdx, 46                     ; POSIX INET6_ADDRSTRLEN
    jb .too_small

    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16                     ; scratch for 8 u16 groups

    mov r12, rdi                    ; src pointer
    mov r13, rsi                    ; dst walker

    ; Decode 8 groups from network-order source into host-order u16s.
    xor ecx, ecx
.load:
    cmp ecx, 8
    jge .find_zeros
    movzx eax, byte [r12 + rcx * 2]
    shl eax, 8
    movzx r8d, byte [r12 + rcx * 2 + 1]
    or eax, r8d
    mov [rsp + rcx * 2], ax
    inc ecx
    jmp .load

.find_zeros:
    ; Find the first-occurring longest run of consecutive zero groups.
    ; Tie-break: strictly-greater update, so the first run wins.
    xor ebx, ebx                    ; best_start
    xor r14d, r14d                  ; best_len
    xor r8d, r8d                    ; cur_start
    xor r9d, r9d                    ; cur_len
    xor ecx, ecx
.scan:
    cmp ecx, 8
    jge .scan_done
    cmp word [rsp + rcx * 2], 0
    jne .not_zero
    test r9d, r9d
    jnz .extend
    mov r8d, ecx
.extend:
    inc r9d
    cmp r9d, r14d
    jle .scan_next
    mov r14d, r9d
    mov ebx, r8d
    jmp .scan_next
.not_zero:
    xor r9d, r9d
.scan_next:
    inc ecx
    jmp .scan
.scan_done:
    ; A run of length 1 does not warrant '::'.
    cmp r14d, 2
    jge .check_v4
    xor r14d, r14d

.check_v4:
    ; IPv4-mapped iff best_start=0, best_len=5, groups[5]=0xffff.
    xor r15d, r15d                  ; use_v4 flag
    cmp r14d, 5
    jne .emit_start
    test ebx, ebx
    jnz .emit_start
    mov ax, [rsp + 10]              ; groups[5]
    cmp ax, 0xffff
    jne .emit_start
    mov r15d, 1

.emit_start:
    xor ecx, ecx                    ; i (group index)
    xor r10d, r10d                  ; need_sep = false

.emit_loop:
    cmp ecx, 8
    jge .emit_done

    ; At the start of the compressed run?
    cmp ecx, ebx
    jne .not_dcolon
    test r14d, r14d
    jz .not_dcolon

    ; Emit "::".
    mov byte [r13], ':'
    inc r13
    mov byte [r13], ':'
    inc r13
    add ecx, r14d                   ; skip the zero run
    xor r10d, r10d                  ; '::' ends with ':', no sep needed
    jmp .emit_loop

.not_dcolon:
    ; Emit ':' between groups when the previous slot already wrote text.
    test r10d, r10d
    jz .no_sep
    mov byte [r13], ':'
    inc r13
.no_sep:

    ; IPv4-mapped tail: at group index 6 emit "a.b.c.d" and stop.
    test r15d, r15d
    jz .emit_hex
    cmp ecx, 6
    jne .emit_hex

    mov al, [r12 + 12]
    call .emit_byte
    mov byte [r13], '.'
    inc r13
    mov al, [r12 + 13]
    call .emit_byte
    mov byte [r13], '.'
    inc r13
    mov al, [r12 + 14]
    call .emit_byte
    mov byte [r13], '.'
    inc r13
    mov al, [r12 + 15]
    call .emit_byte
    jmp .emit_done

.emit_hex:
    movzx eax, word [rsp + rcx * 2]
    call .emit_group
    mov r10d, 1                     ; next group needs a separator
    inc ecx
    jmp .emit_loop

.emit_done:
    mov byte [r13], 0               ; NUL-terminate
    mov rax, rsi                    ; return the caller's dst
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.too_small:
    xor eax, eax
    ret

; ---- internal helpers ----

; .emit_group(eax: u16) — emit 1..4 lowercase hex digits at [r13].
;   Suppresses leading zero nibbles; a zero value emits "0".
;   Preserves ecx, r10d, r14d, ebx, r12, r13-advanced.
;   Clobbers eax, edx, r11d.
.emit_group:
    test eax, eax
    jnz .eg_nonzero
    mov byte [r13], '0'
    inc r13
    ret

.eg_nonzero:
    mov edx, eax                    ; keep original value in edx
    xor r11d, r11d                  ; started = false

    ; Nibble at bits 12..15
    mov eax, edx
    shr eax, 12
    and eax, 0xf
    jz .eg_skip_12
    mov r11d, 1
    call .hex_char
    mov [r13], al
    inc r13
.eg_skip_12:

    ; Nibble at bits 8..11
    mov eax, edx
    shr eax, 8
    and eax, 0xf
    jnz .eg_emit_8
    test r11d, r11d
    jz .eg_skip_8
.eg_emit_8:
    mov r11d, 1
    call .hex_char
    mov [r13], al
    inc r13
.eg_skip_8:

    ; Nibble at bits 4..7
    mov eax, edx
    shr eax, 4
    and eax, 0xf
    jnz .eg_emit_4
    test r11d, r11d
    jz .eg_skip_4
.eg_emit_4:
    call .hex_char
    mov [r13], al
    inc r13
.eg_skip_4:

    ; Nibble at bits 0..3 — always emitted.
    mov eax, edx
    and eax, 0xf
    call .hex_char
    mov [r13], al
    inc r13
    ret

; .hex_char(al: 0..15) — return ASCII lowercase hex in al.
;   Preserves all other registers.
.hex_char:
    cmp al, 10
    jb .hc_dec
    add al, 'a' - 10
    ret
.hc_dec:
    add al, '0'
    ret

; .emit_byte(al: 0..255) — emit 1..3 decimal digits at [r13].
;   Reached only from the IPv4-tail path, which terminates the
;   emit loop immediately after — safe to clobber eax/ecx/edx.
.emit_byte:
    movzx eax, al
    cmp eax, 100
    jb .eb_lt100
    mov ecx, 100
    xor edx, edx
    div ecx
    add al, '0'
    mov [r13], al
    inc r13
    mov eax, edx
    jmp .eb_two
.eb_lt100:
    cmp eax, 10
    jb .eb_one
.eb_two:
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov [r13], al
    inc r13
    add dl, '0'
    mov [r13], dl
    inc r13
    ret
.eb_one:
    add al, '0'
    mov [r13], al
    inc r13
    ret
