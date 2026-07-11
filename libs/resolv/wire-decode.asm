; resolv_decode_response(buf: rdi, len: rsi, expected_id: rdx,
;                        out_ip: rcx) -> rax = 0 or negative errno
;
; Parses a DNS response, validates it, and copies the first A
; record's four RDATA bytes to *out_ip*.
;
; Error mapping (all returns negative on failure):
;
;   -EBADMSG (-74) — the response is shorter than 12 bytes, or
;                    is malformed (bad label length, RDLENGTH
;                    that overruns the buffer, corrupted
;                    compression pointer, ID mismatch, QR bit
;                    is 0)
;   -ENOENT  (-2)  — RCODE 3 (NXDOMAIN): name does not exist
;   -EIO     (-5)  — RCODE 2 (SERVFAIL) or any RCODE this
;                    decoder does not have a more specific
;                    mapping for
;   -ENODATA (-96 on Linux, -96 on macOS)
;                  — the response was well-formed and RCODE=0
;                    but no answer of TYPE=A / CLASS=IN was
;                    found (e.g. only CNAMEs, or an empty
;                    answer section)
;
; On success returns 0 and writes 4 bytes of network-order
; IPv4 address to *out_ip*.
;
; Name-compression pointers (RFC 1035 §4.1.4): a byte with the
; top two bits set (0xC0..0xFF) is a two-byte pointer whose
; low 14 bits are an offset from the start of the DNS message.
; The decoder does not need to actually resolve the compressed
; name (we only care about the A record's TYPE / CLASS /
; RDLENGTH / RDATA, which follow the name) — it just needs to
; walk past the name correctly.

%include "syscall.inc"

default rel

global resolv_decode_response

section .text

%define TYPE_A       1
%define CLASS_IN     1

; Register roles inside the function:
;   r12 = buf base pointer
;   r13 = end-of-buffer pointer (buf + len)  (bounds check)
;   r14 = cursor (walks through the message)
;   ebx = answer count remaining
;   rbp = out_ip pointer (survives every internal step)

resolv_decode_response:
    push rbx
    push rbp
    push r12
    push r13
    push r14

    mov r12, rdi                    ; buf base
    lea r13, [rdi + rsi]            ; buf end
    mov rbp, rcx                    ; out_ip

    ; --------------------------------------------------------------
    ; Header (12 bytes total)
    ; --------------------------------------------------------------
    cmp rsi, 12
    jb .badmsg                      ; too short to hold a header

    ; ID check: bytes 0..1 network-order == expected_id host-order
    movzx eax, word [r12]
    rol ax, 8                       ; net → host
    movzx ecx, dx
    cmp ax, cx
    jne .badmsg

    ; Flags check: byte 2 has QR in the high bit. Reject if QR=0.
    movzx eax, byte [r12 + 2]
    test al, 0x80
    jz .badmsg

    ; RCODE lives in the low four bits of byte 3.
    movzx eax, byte [r12 + 3]
    and eax, 0x0f
    cmp eax, 0
    je .rcode_ok
    cmp eax, 3
    je .nxdomain
    ; Any other RCODE — treat as SERVFAIL.
    jmp .servfail

.rcode_ok:
    ; ANCOUNT — bytes 6..7 net order. Zero here means "well-formed
    ; but empty answer" → -ENODATA.
    movzx eax, word [r12 + 6]
    rol ax, 8
    test eax, eax
    jz .nodata
    mov ebx, eax                    ; answers to walk

    ; Cursor points to the question section (byte 12).
    lea r14, [r12 + 12]

    ; QDCOUNT: assume 1 (we sent it). Skip its labels + QTYPE +
    ; QCLASS. If the response echoes back a different QDCOUNT the
    ; skip loop still terminates because it stops at the
    ; terminating zero-label.
    call .skip_name
    test rax, rax
    js .badmsg
    add r14, 4                      ; QTYPE + QCLASS
    cmp r14, r13
    ja .badmsg

    ; --------------------------------------------------------------
    ; Answer section — walk records until an A/IN is found.
    ; --------------------------------------------------------------
.next_answer:
    test ebx, ebx
    jz .nodata

    ; NAME
    call .skip_name
    test rax, rax
    js .badmsg

    ; TYPE (2) + CLASS (2) + TTL (4) + RDLENGTH (2) = 10 bytes
    lea rax, [r14 + 10]
    cmp rax, r13
    ja .badmsg

    movzx r8d, word [r14]
    rol r8w, 8
    movzx r9d, word [r14 + 2]
    rol r9w, 8

    ; TTL at r14+4..r14+7 — we do not need it.
    movzx r10d, word [r14 + 8]
    rol r10w, 8                     ; RDLENGTH (host order)

    lea r14, [r14 + 10]             ; advance past TYPE/CLASS/TTL/RDLENGTH
    ; Verify RDLENGTH does not overrun the buffer.
    lea rax, [r14 + r10]
    cmp rax, r13
    ja .badmsg

    ; TYPE = A and CLASS = IN?
    cmp r8w, TYPE_A
    jne .skip_rdata
    cmp r9w, CLASS_IN
    jne .skip_rdata
    cmp r10w, 4
    jne .badmsg                     ; A record must have exactly 4 bytes

    ; Copy the four RDATA bytes into *out_ip.
    mov al, [r14]
    mov [rbp], al
    mov al, [r14 + 1]
    mov [rbp + 1], al
    mov al, [r14 + 2]
    mov [rbp + 2], al
    mov al, [r14 + 3]
    mov [rbp + 3], al

    xor eax, eax                    ; success
    jmp .done

.skip_rdata:
    add r14, r10
    dec ebx
    jmp .next_answer

.badmsg:
    mov rax, -74                    ; -EBADMSG
    jmp .done
.nxdomain:
    mov rax, -2                     ; -ENOENT
    jmp .done
.servfail:
    mov rax, -5                     ; -EIO
    jmp .done
.nodata:
    ; -ENODATA differs by platform: Linux uses 61, macOS uses 96.
%ifdef MACOS
    mov rax, -96
%else
    mov rax, -61
%endif

.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- .skip_name ----------------------------------------------
; Walks r14 past a DNS name (labels or a compression pointer).
; Returns rax = 0 on success (r14 now points at the byte after
; the name), or -1 on malformed input.
;
; Uses caller registers r13 (end) and r14 (cursor); clobbers
; rax, rcx.
.skip_name:
    xor eax, eax
.sn_loop:
    cmp r14, r13
    jae .sn_bad                     ; out of bounds
    movzx ecx, byte [r14]
    test cl, cl
    jz .sn_zero
    cmp cl, 0xC0
    jae .sn_pointer
    cmp cl, 0x3F
    ja .sn_bad                      ; length between 64 and 191 is invalid
    ; Normal length-prefixed label — skip the length byte plus cl chars.
    inc r14                         ; over length byte
    add r14, rcx                    ; over label chars
    cmp r14, r13
    ja .sn_bad
    jmp .sn_loop
.sn_zero:
    inc r14                         ; consume the zero-label
    ret
.sn_pointer:
    ; Two-byte pointer. We only need to walk PAST the name, not
    ; resolve it, so skip both bytes and we are done.
    add r14, 2
    cmp r14, r13
    ja .sn_bad
    ret
.sn_bad:
    mov rax, -1
    ret
