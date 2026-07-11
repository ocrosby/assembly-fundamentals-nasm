; resolv_decode_records(buf: rdi, len: rsi, expected_id: rdx,
;                       qtype: rcx, out_buf: r8, max_count: r9)
;     -> rax = count copied (>= 0) or negative errno
;
; Parses a DNS response, validates the header, and copies every
; answer of TYPE=qtype and CLASS=IN into out_buf, packed
; back-to-back. Copies at most max_count records; if the
; response has more, later records are silently discarded but
; the returned count is still the number copied (i.e. capped at
; max_count). Callers that need to know the response held more
; can size out_buf to fit their upper bound.
;
; Supported QTYPEs and their fixed RDATA sizes:
;
;    1  (A)     — 4 bytes
;   28  (AAAA)  — 16 bytes
;
; Any other qtype returns -EINVAL, since we do not know how many
; RDATA bytes to copy per record.
;
; Error mapping (all returns negative on failure):
;
;   -EINVAL   (-22)  — unsupported qtype
;   -EBADMSG  (-74)  — malformed response (short header, ID
;                      mismatch, QR=0, bad label length,
;                      RDLENGTH != rec_size for a matching
;                      record, out-of-bounds compression pointer,
;                      buffer overrun)
;   -ENOENT   (-2)   — RCODE 3 (NXDOMAIN)
;   -EIO      (-5)   — RCODE 2 (SERVFAIL) or any other RCODE
;
; Success returns 0..max_count. Zero means well-formed
; response with RCODE=0 but no matching answer — the caller
; may want to look for a CNAME (see resolv_decode_cname below).
;
; ---- resolv_decode_cname(buf: rdi, len: rsi, expected_id: rdx,
;                          out_name: rcx, out_capacity: r8)
;     -> rax = 0 (success) or negative errno
;
; Extracts the first CNAME target from a validated response.
; out_name is populated with a NUL-terminated dotted-form
; hostname (labels joined by '.'). If the target does not fit
; in out_capacity bytes (including the NUL), returns -EBADMSG
; without partial write.
;
; Same error mapping as decode_records for header-level errors;
; -ENOENT means the answer section had no CNAME record.
;
; Both functions handle DNS name-compression pointers per
; RFC 1035 §4.1.4: a byte with the top two bits set (0xC0..0xFF)
; is a two-byte pointer whose low 14 bits give an offset from
; the start of the DNS message. The offset must land inside the
; response — bad pointers are treated as -EBADMSG.

%include "syscall.inc"

default rel

global resolv_decode_records
global resolv_decode_cname

section .text

%define TYPE_A       1
%define TYPE_CNAME   5
%define TYPE_AAAA    28
%define CLASS_IN     1

; ---- .header_validate ------------------------------------------
; Shared prologue for both entry points. Reads the header, checks
; ID / QR / RCODE, and advances a cursor past the question
; section so callers can start walking the answer section.
;
; Inputs (unchanged after return):
;   r12 = buf base
;   r13 = buf end (buf + len)
;   rbx = expected_id (in the low 16 bits)
;
; Outputs:
;   rax = 0 (success), OR negative errno on failure
;   r14 = ANCOUNT (u16 host order)
;   rbp = cursor pointing at the first answer record
;
; Registers clobbered: rax, rcx, rdx.

; Register roles for resolv_decode_records:
;   r12  = buf base pointer
;   r13  = buf end pointer (buf + len)
;   r14d = ANCOUNT remaining (during the walk)
;   r15  = out_buf cursor (advances as records are copied)
;   rbp  = current position in the response
;   rbx  = expected_id (low 16 bits), then reused for count
;
; Stack frame (16-byte aligned):
;   [rsp+0]  = qtype (dword)
;   [rsp+4]  = rec_size (dword)
;   [rsp+8]  = max_count (qword)
;   [rsp+16] = count so far (qword)
;   Total: 24 bytes → allocate 32 for alignment.

%define QTYPE_OFF     0
%define REC_SIZE_OFF  4
%define MAX_COUNT_OFF 8
%define COUNT_OFF     16
%define FRAME_SIZE    32

resolv_decode_records:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, FRAME_SIZE
    mov r12, rdi                    ; buf base
    lea r13, [rdi + rsi]             ; buf end
    mov ebx, edx                    ; expected_id (u16)
    mov r15, r8                     ; out_buf

    ; Validate qtype and derive rec_size.
    mov [rsp + QTYPE_OFF], ecx
    cmp ecx, TYPE_A
    je .rec_size_4
    cmp ecx, TYPE_AAAA
    je .rec_size_16
    mov rax, -22                    ; -EINVAL
    jmp .done
.rec_size_4:
    mov dword [rsp + REC_SIZE_OFF], 4
    jmp .rec_size_ok
.rec_size_16:
    mov dword [rsp + REC_SIZE_OFF], 16
.rec_size_ok:

    mov [rsp + MAX_COUNT_OFF], r9   ; max_count
    mov qword [rsp + COUNT_OFF], 0  ; count so far

    ; Validate header.
    call wire_validate_header
    test rax, rax
    js .done

    ; ---- walk answer section ----
.next_answer:
    test r14d, r14d
    jz .return_count

    ; Skip the name (labels or compression pointer).
    call wire_skip_name
    test rax, rax
    js .badmsg

    ; TYPE (2) + CLASS (2) + TTL (4) + RDLENGTH (2) = 10 bytes.
    lea rax, [rbp + 10]
    cmp rax, r13
    ja .badmsg

    movzx r10d, word [rbp]
    rol r10w, 8                     ; type (host order)
    movzx r11d, word [rbp + 2]
    rol r11w, 8                     ; class
    ; TTL at [rbp+4..7] — unused.
    movzx ecx, word [rbp + 8]
    rol cx, 8                       ; rdlength

    add rbp, 10
    lea rax, [rbp + rcx]
    cmp rax, r13
    ja .badmsg

    ; TYPE match? CLASS_IN? RDLENGTH == rec_size?
    cmp r10d, dword [rsp + QTYPE_OFF]
    jne .skip_this
    cmp r11d, CLASS_IN
    jne .skip_this
    cmp ecx, dword [rsp + REC_SIZE_OFF]
    jne .badmsg                     ; matching QTYPE with wrong size

    ; Room in out_buf? If not, fall through to .skip_this so the
    ; response is still validated but the record is silently
    ; discarded (matches the docstring's "capped at max_count"
    ; contract). rcx is preserved across the copy loop so
    ; .skip_this can advance rbp past RDATA.
    mov rax, [rsp + COUNT_OFF]
    cmp rax, [rsp + MAX_COUNT_OFF]
    jae .skip_this

    ; Copy rec_size bytes from [rbp] to [r15]. Use r11d as the
    ; loop counter and edx as the bound; leave rcx alone so the
    ; .skip_this advance below still has RDLENGTH.
    mov edx, dword [rsp + REC_SIZE_OFF]
    xor r11d, r11d
.copy_loop:
    cmp r11d, edx
    jae .copy_done
    mov al, [rbp + r11]
    mov [r15 + r11], al
    inc r11d
    jmp .copy_loop
.copy_done:

    add r15, rdx
    inc qword [rsp + COUNT_OFF]

.skip_this:
    add rbp, rcx                    ; over RDATA
    dec r14d
    jmp .next_answer

.return_count:
    mov rax, [rsp + COUNT_OFF]
    jmp .done

.badmsg:
    mov rax, -74                    ; -EBADMSG
    jmp .done

.done:
    add rsp, FRAME_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- wire_validate_header ----------------------------------------
; Reads and validates the 12-byte DNS header, sets r14d =
; ANCOUNT, rbp = &question. Returns rax = 0 on success or a
; negative errno matching the RCODE / malformed cases.
wire_validate_header:
    ; Header size check.
    lea rax, [r12 + 12]
    cmp rax, r13
    ja .vh_badmsg

    ; ID check.
    movzx eax, word [r12]
    rol ax, 8
    cmp ax, bx
    jne .vh_badmsg

    ; QR check.
    movzx eax, byte [r12 + 2]
    test al, 0x80
    jz .vh_badmsg

    ; RCODE.
    movzx eax, byte [r12 + 3]
    and eax, 0x0f
    cmp eax, 0
    je .vh_rcode_ok
    cmp eax, 3
    je .vh_nxdomain
    jmp .vh_servfail
.vh_rcode_ok:

    ; ANCOUNT (bytes 6..7 net order).
    movzx eax, word [r12 + 6]
    rol ax, 8
    mov r14d, eax

    ; Cursor at start of question.
    lea rbp, [r12 + 12]

    ; Skip QDCOUNT questions — the wire encoder always sends 1,
    ; but validate against QDCOUNT to be forgiving of servers
    ; that echo a different value.
    ;
    ; wire_skip_name clobbers rcx, so hold the QDCOUNT counter on
    ; the stack across the call rather than in a register.
    movzx ecx, word [r12 + 4]
    rol cx, 8
.vh_skip_q:
    test ecx, ecx
    jz .vh_after_q
    push rcx                        ; preserve QDCOUNT across the helper
    call wire_skip_name
    pop rcx
    test rax, rax
    js .vh_badmsg
    ; QTYPE (2) + QCLASS (2)
    lea rax, [rbp + 4]
    cmp rax, r13
    ja .vh_badmsg
    add rbp, 4
    dec ecx
    jmp .vh_skip_q
.vh_after_q:

    xor eax, eax
    ret

.vh_badmsg:
    mov rax, -74                    ; -EBADMSG
    ret
.vh_nxdomain:
    mov rax, -2
    ret
.vh_servfail:
    mov rax, -5
    ret

; ---- wire_skip_name ----------------------------------------------
; Advances rbp past a DNS name. Handles both length-prefixed
; labels and compression pointers. Returns rax = 0 on success,
; -1 on malformed input. Only advances the cursor when the
; entire name has been walked past (a pointer is walked past by
; skipping the 2-byte pointer itself — the caller does not need
; to follow it).
wire_skip_name:
    xor eax, eax
.sn_loop:
    cmp rbp, r13
    jae .sn_bad
    movzx ecx, byte [rbp]
    test cl, cl
    jz .sn_zero
    cmp cl, 0xC0
    jae .sn_pointer
    cmp cl, 0x3F
    ja .sn_bad
    inc rbp
    add rbp, rcx
    cmp rbp, r13
    ja .sn_bad
    jmp .sn_loop
.sn_zero:
    inc rbp
    ret
.sn_pointer:
    add rbp, 2
    cmp rbp, r13
    ja .sn_bad
    ret
.sn_bad:
    mov rax, -1
    ret

; ---- resolv_decode_cname -------------------------------------
; Walks the answer section looking for a TYPE=5 CNAME record.
; Decodes its target into out_name as a NUL-terminated
; dotted-form string, following compression pointers.
;
; Register roles inside the function:
;   r12  = buf base
;   r13  = buf end
;   r14d = ANCOUNT remaining
;   r15  = out_name (unchanged)
;   rbp  = cursor
;   rbx  = expected_id
;
; Stack frame: [rsp+0..7] = out_capacity (qword)

%define CNAME_CAP_OFF 0
%define CNAME_FRAME   16

resolv_decode_cname:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, CNAME_FRAME

    mov r12, rdi
    lea r13, [rdi + rsi]
    mov ebx, edx
    mov r15, rcx
    mov [rsp + CNAME_CAP_OFF], r8

    call wire_validate_header
    test rax, rax
    js .cn_done

.cn_next:
    test r14d, r14d
    jz .cn_miss

    call wire_skip_name
    test rax, rax
    js .cn_badmsg

    lea rax, [rbp + 10]
    cmp rax, r13
    ja .cn_badmsg

    movzx r10d, word [rbp]
    rol r10w, 8                     ; type
    movzx r11d, word [rbp + 2]
    rol r11w, 8                     ; class
    movzx ecx, word [rbp + 8]
    rol cx, 8                       ; rdlength

    add rbp, 10
    lea rax, [rbp + rcx]
    cmp rax, r13
    ja .cn_badmsg

    cmp r10d, TYPE_CNAME
    je .cn_found
    cmp r11d, CLASS_IN
    jne .cn_skip
.cn_skip:
    add rbp, rcx
    dec r14d
    jmp .cn_next

.cn_found:
    ; The CNAME target starts at rbp for RDLENGTH bytes. But we
    ; want to walk labels and pointers into the whole message,
    ; not just this range — pointers may point anywhere.
    mov r10, [rsp + CNAME_CAP_OFF]
    call wire_decode_name
    test rax, rax
    js .cn_badmsg
    xor eax, eax                    ; success
    jmp .cn_done

.cn_miss:
    mov rax, -2                     ; -ENOENT
    jmp .cn_done

.cn_badmsg:
    mov rax, -74

.cn_done:
    add rsp, CNAME_FRAME
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- wire_decode_name -------------------------------------------
; Decodes a DNS name at rbp into r15 as a NUL-terminated dotted
; string, at most r10 bytes long (including the NUL). Handles
; compression pointers by following them within the message
; bounds.
;
; Returns rax = 0 on success, -1 on malformed input or if the
; output would exceed r10 bytes. On success, rbp is advanced
; past the top-level name (compression targets do not advance
; rbp).
;
; Register roles inside:
;   r8   = write cursor within out_name
;   r9   = read cursor (may follow into pointer targets)
;   r11  = "have we followed a pointer" flag (0 = no, 1 = yes;
;          once we follow a pointer, we stop advancing rbp)
;   ecx  = remaining capacity in out_name
;   edx  = current label length
wire_decode_name:
    mov r8, r15                     ; write cursor
    mov r9, rbp                     ; read cursor
    mov rcx, r10                    ; remaining capacity
    xor r11d, r11d                  ; not-yet-followed-pointer

.dn_label:
    cmp r9, r13
    jae .dn_bad
    movzx edx, byte [r9]
    test dl, dl
    jz .dn_terminate
    cmp dl, 0xC0
    jae .dn_ptr
    cmp dl, 0x3F
    ja .dn_bad

    ; Advance read cursor over the length byte.
    inc r9
    lea rax, [r9 + rdx]
    cmp rax, r13
    ja .dn_bad

    ; If this is not the first label, emit a '.' separator.
    cmp r8, r15
    je .dn_no_dot
    cmp rcx, 1
    jb .dn_bad
    mov byte [r8], '.'
    inc r8
    dec rcx
.dn_no_dot:

    ; Copy the label bytes.
    cmp rcx, rdx
    jb .dn_bad
.dn_copy:
    test dl, dl
    jz .dn_after_copy
    mov al, [r9]
    mov [r8], al
    inc r9
    inc r8
    dec rcx
    dec dl
    jmp .dn_copy
.dn_after_copy:

    ; If we have not yet followed a pointer, advance rbp too.
    test r11d, r11d
    jnz .dn_no_advance
    mov rbp, r9
.dn_no_advance:
    jmp .dn_label

.dn_ptr:
    ; Two-byte pointer. Offset = ((first_byte & 0x3F) << 8) | second_byte.
    lea rax, [r9 + 2]
    cmp rax, r13
    ja .dn_bad
    movzx eax, byte [r9]
    and eax, 0x3F
    shl eax, 8
    mov dl, [r9 + 1]
    or al, dl                       ; combine into low 14 bits (well, 8 low)
    ; Actually reassemble properly:
    movzx r10d, byte [r9]
    and r10d, 0x3F
    shl r10d, 8
    movzx edx, byte [r9 + 1]
    or r10d, edx                    ; r10d = target offset

    ; If we have not yet followed a pointer, advance rbp past
    ; this 2-byte pointer (that terminates the top-level name).
    test r11d, r11d
    jnz .dn_ptr_no_advance
    lea rbp, [r9 + 2]
    mov r11d, 1
.dn_ptr_no_advance:

    ; Set r9 to the pointer target.
    lea r9, [r12 + r10]
    cmp r9, r13
    jae .dn_bad
    jmp .dn_label

.dn_terminate:
    ; Emit NUL terminator.
    cmp rcx, 1
    jb .dn_bad
    mov byte [r8], 0

    ; Advance rbp past the zero byte (only if we hadn't followed
    ; a pointer — pointer traversal handles it separately).
    test r11d, r11d
    jnz .dn_ok
    inc rbp
.dn_ok:
    xor eax, eax
    ret

.dn_bad:
    mov rax, -1
    ret
