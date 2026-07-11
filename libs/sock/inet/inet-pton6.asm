; inet_pton6(src: rdi, dst: rsi) -> rax = 1 on success, 0 on failure
;
; Parses an RFC 4291 IPv6 address string into 16 bytes at *dst in
; network byte order. Supports:
;
;   * Full form:      2001:db8:85a3:0:0:8a2e:370:7334
;   * :: compression: ::1, 1::, ::, 1::2:3
;   * IPv4-mapped:    ::ffff:192.0.2.1
;   * Mixed case hex
;
; Rejects (returning 0):
;
;   * More than 8 groups, fewer than 8 groups without ::
;   * More than one :: (RFC 4291 §2.2 rule 2)
;   * :: expanding to zero groups (e.g. 1:2:3:4:5:6:7:8::)
;   * More than 4 hex digits in a group
;   * Malformed IPv4 tail (leading zeros in an octet, out-of-range
;     octet, missing octets, trailing garbage)
;   * A bare IPv4 dotted quad with no leading '::' prefix
;   * A leading single ':' that is not part of '::'
;   * A trailing single ':'
;   * Scope IDs like '%eth0' — POSIX inet_pton() does not support
;     these, and the resolver-layer semantics are ambiguous.
;
; Parse strategy: read groups left-to-right into a stack-local
; 8×u16 scratch, recording where '::' appeared (if any) as an
; index into that scratch. On successful parse, expand '::' by
; shifting the "after" groups to the tail of the 16-byte output
; and zero-filling the gap. This keeps *dst untouched on failure.

default rel

global inet_pton6

section .text

; Register roles for the duration of the function:
;   r12 = src walker
;   r13 = final dst pointer (16-byte output)
;   rbp = stack scratch base (16 bytes of 8 u16s, pre-zeroed)
;   ebx = number of groups parsed so far (0..8)
;   r14d = index at which '::' appeared, or -1 sentinel
;   r15  = general scratch (dotted-quad byte pointer, tail copy dst)

inet_pton6:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16                     ; 16-byte scratch for 8 u16 groups

    mov qword [rsp], 0              ; pre-zero scratch — unparsed groups
    mov qword [rsp + 8], 0          ; stay zero (idempotent expansion)

    mov r12, rdi                    ; src walker
    mov r13, rsi                    ; final dst
    mov rbp, rsp                    ; scratch base
    xor ebx, ebx                    ; total groups so far
    mov r14d, -1                    ; dcolon_at = sentinel

    ; Peek first char: leading ':' must be part of '::'.
    cmp byte [r12], ':'
    jne .parse_group
    cmp byte [r12 + 1], ':'
    jne .fail
    add r12, 2
    mov r14d, 0                     ; dcolon_at = 0
    cmp byte [r12], 0
    je .assemble                    ; input was just "::"
    ; fall through to parse first post-:: group

.parse_group:
    ; Read 1..4 hex digits into eax. Track "saw hex letter" in edx
    ; so the dotted-quad path can veto if any A-F was seen.
    xor eax, eax                    ; group value accumulator
    xor ecx, ecx                    ; digit count
    xor edx, edx                    ; saw_hex_letter flag

.hex_loop:
    movzx r8d, byte [r12]

    ; Try decimal '0'..'9'
    mov r9d, r8d
    sub r9d, '0'
    cmp r9d, 9
    jbe .hex_got_digit

    ; Try hex 'A'..'F' / 'a'..'f' (case-insensitive via or 0x20).
    mov r9d, r8d
    or r9d, 0x20
    sub r9d, 'a'
    cmp r9d, 5
    ja .hex_end                     ; not a hex char, stop
    add r9d, 10                     ; hex value 10..15
    mov edx, 1                      ; saw a letter → not decimal

.hex_got_digit:
    inc ecx
    cmp ecx, 5                      ; >4 hex digits in a group
    je .fail
    shl eax, 4
    or eax, r9d
    inc r12
    jmp .hex_loop

.hex_end:
    ; r8b holds the stopping char (NUL, ':' , '.' , or garbage).
    cmp r8b, '.'
    je .dotted_quad                 ; embedded IPv4 tail

    ; A hex group must have had at least one digit — a bare ':' or
    ; NUL here means the caller consumed a colon and no digit
    ; followed, which is a syntactic error.
    test ecx, ecx
    jz .fail

    ; Store the parsed group as a u16 in network byte order.
    cmp ebx, 8
    jge .fail                       ; too many groups already
    xchg al, ah                     ; byte-swap ax
    mov [rbp + rbx * 2], ax
    inc ebx

    test r8b, r8b
    jz .assemble                    ; end of input

    cmp r8b, ':'
    jne .fail
    inc r12                         ; consume the ':'
    cmp byte [r12], ':'
    je .double_colon
    jmp .parse_group

.double_colon:
    cmp r14d, -1
    jne .fail                       ; a second '::' is invalid
    mov r14d, ebx                   ; dcolon_at = current position
    inc r12                         ; consume the second ':'
    cmp byte [r12], 0
    je .assemble                    ; trailing '::'
    jmp .parse_group

.dotted_quad:
    ; The "hex digits" we just read were actually the first octet of
    ; an IPv4 tail, and the '.' after them proves it. Requirements:
    ;   * no hex letter was seen (edx == 0)
    ;   * two more scratch groups are available (ebx <= 6)
    ;   * we must have a leading '::' or 6 explicit hex groups so the
    ;     tail lands at bytes 12..16 — but that check is deferred to
    ;     the .assemble stage via the head/tail split, so we only
    ;     verify the parse itself here.
    test edx, edx
    jnz .fail
    cmp ebx, 7
    jg .fail                        ; needs 2 more group slots

    ; Rewind r12 past the digits we consumed as hex — the dotted
    ; parser wants to start at the first digit of octet 0.
    sub r12, rcx

    lea r15, [rbp + rbx * 2]        ; dest byte pointer
    mov r8d, 4                      ; octets remaining

.dq_octet:
    ; Read the first digit of this octet.
    movzx r9d, byte [r12]
    sub r9d, '0'
    cmp r9d, 9
    ja .fail                        ; must have at least one digit
    inc r12

    test r9d, r9d
    jnz .dq_accum

    ; First digit is '0': strict form forbids leading zeros, so the
    ; octet must be exactly "0".
    movzx eax, byte [r12]
    sub eax, '0'
    cmp eax, 9
    jbe .fail                       ; another digit follows the '0'
    xor eax, eax                    ; octet value = 0
    jmp .dq_store

.dq_accum:
    mov eax, r9d
.dq_accum_loop:
    movzx r9d, byte [r12]
    sub r9d, '0'
    cmp r9d, 9
    ja .dq_store
    lea eax, [eax + eax * 4]        ; eax *= 5
    lea eax, [r9 + rax * 2]         ; eax = eax*10 + digit
    cmp eax, 255
    ja .fail
    inc r12
    jmp .dq_accum_loop

.dq_store:
    mov [r15], al
    inc r15
    dec r8d
    jz .dq_end

    ; Between octets: '.'
    movzx r9d, byte [r12]
    cmp r9b, '.'
    jne .fail
    inc r12
    jmp .dq_octet

.dq_end:
    ; After the last octet we require NUL — no trailing text and no
    ; more IPv6 groups after the IPv4 tail.
    movzx r9d, byte [r12]
    test r9b, r9b
    jnz .fail
    add ebx, 2                      ; consumed two 16-bit groups
    ; fall through to .assemble

.assemble:
    ; Scratch now holds `ebx` groups in the order they appeared. If
    ; '::' was present, r14d tells us where to split for expansion.
    cmp r14d, -1
    je .assemble_full

    ; With '::' the total group count must leave room for at least
    ; one zero — RFC 4291 forbids '::' expanding to zero groups.
    cmp ebx, 8
    jge .fail

    ; head_count = r14d (groups before '::')
    ; tail_count = ebx - r14d (groups after '::')
    ; dst layout: [head][zeros][tail]
    ;   dst[0 ..              head*2] = scratch[0 .. head*2]
    ;   dst[head*2 ..     (8-tail)*2] = 0
    ;   dst[(8-tail)*2 ..         16] = scratch[head*2 .. ebx*2]

    ; head_bytes = r14d * 2 → r10d
    mov r10d, r14d
    shl r10d, 1

    ; Copy head_bytes from scratch to dst.
    xor r8d, r8d
.head_loop:
    cmp r8d, r10d
    jge .head_done
    mov al, [rbp + r8]
    mov [r13 + r8], al
    inc r8d
    jmp .head_loop
.head_done:

    ; tail_bytes = (ebx - r14d) * 2 → r11d
    mov r11d, ebx
    sub r11d, r14d
    shl r11d, 1

    ; tail_dst_offset = 16 - tail_bytes → r9d
    mov r9d, 16
    sub r9d, r11d

    ; Zero the gap: dst[r10d .. r9d]
    mov r8d, r10d
.gap_loop:
    cmp r8d, r9d
    jge .gap_done
    mov byte [r13 + r8], 0
    inc r8d
    jmp .gap_loop
.gap_done:

    ; Copy tail_bytes from scratch[head_bytes] to dst[tail_dst_offset].
    ; x86-64 addressing modes allow at most base+index — precompute
    ; the tail source and destination bases so the copy loop uses
    ; only [base + counter] indexing.
    lea rdi, [rbp + r10]            ; scratch source after head
    lea rsi, [r13 + r9]              ; dst at gap end
    xor r8d, r8d
.tail_loop:
    cmp r8d, r11d
    jge .success
    mov al, [rdi + r8]
    mov [rsi + r8], al
    inc r8d
    jmp .tail_loop

.assemble_full:
    ; No '::' — must have exactly 8 groups.
    cmp ebx, 8
    jne .fail
    mov rax, [rbp]
    mov [r13], rax
    mov rax, [rbp + 8]
    mov [r13 + 8], rax

.success:
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
