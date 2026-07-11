; resolv_encode_query(name: rdi, id: rsi, qtype: rdx, out_buf: rcx)
;     -> rax = total bytes written, or -EINVAL on malformed name
;
; Builds a well-formed DNS query for the requested QTYPE
; (typically 1 for A or 28 for AAAA — the encoder does not
; validate qtype; the wire format is the same for any RR type
; and the resolver rejects anything it cannot decode). The
; output at *out_buf* looks like:
;
;     +-------------------------------+ 12 bytes
;     |  DNS header                   |
;     |    ID       = id (u16, net)   |
;     |    Flags    = 0x0100 (net) — standard query, RD set
;     |    QDCOUNT  = 1  (net)
;     |    ANCOUNT  = 0
;     |    NSCOUNT  = 0
;     |    ARCOUNT  = 0
;     +-------------------------------+
;     |  QNAME: length-prefixed labels |
;     |    e.g. "example.com" becomes  |
;     |    07 e x a m p l e            |
;     |    03 c o m                    |
;     |    00                          |
;     +-------------------------------+
;     |  QTYPE  = qtype (u16, net)     |
;     |  QCLASS = 1  (IN, net)         |
;     +-------------------------------+
;
; Returns the total encoded length in rax. Callers use that to
; drive sendto() so no padding is transmitted.
;
; Rejects (returning -EINVAL):
;
;   * An empty name
;   * A single label longer than 63 octets (DNS spec ceiling)
;   * A leading '.' (empty label at position 0)
;   * Two consecutive '.' (empty label mid-name)
;   * A trailing '.' — RFC-legal but the parser here treats a
;     terminating zero-label explicitly and does not accept
;     the shorthand form
;   * A total wire length exceeding 512 bytes (UDP DNS max)
;
; No syscalls, no allocations. All work happens in registers
; and writes directly to *out_buf*.

%include "syscall.inc"

default rel

global resolv_encode_query

section .text

%define QCLASS_IN 1

; Register roles for the duration of the function:
;   r10d= qtype (u16 in low bits; caller-saved, safe here
;               because we make no calls)
;   r12 = name walker (advances one char at a time)
;   r13 = out cursor  (advances as bytes are written)
;   r14 = out base    (unchanged; used to compute final length)
;   ebx = current label length (0..63; capped)
;   r15 = label-length address (the byte we will backfill once
;         we know how long the label was)

resolv_encode_query:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Reject NULL/empty name up front: if *name == '\0', bail
    ; before we've written any bytes so callers see -EINVAL and
    ; not a zero-length "success".
    movzx eax, byte [rdi]
    test al, al
    jz .invalid

    mov r12, rdi                    ; name walker
    mov r13, rcx                    ; out cursor
    mov r14, rcx                    ; out base
    mov r10d, edx                   ; qtype (u16 in low bits)

    ; ---- Header (12 bytes) ----
    ; ID (u16 net): swap host-order id then store big-endian.
    ; rsi carries the id as a u16 host-order value.
    mov ax, si
    rol ax, 8
    mov [r13], ax                   ; bytes 0..1: ID
    ; Flags: 0x0100 (RD set) in network byte order = 01 00.
    mov word [r13 + 2], 0x0001
    ; QDCOUNT = 1 (net): 00 01
    mov word [r13 + 4], 0x0100
    ; ANCOUNT / NSCOUNT / ARCOUNT: all 0
    mov word [r13 + 6], 0
    mov word [r13 + 8], 0
    mov word [r13 + 10], 0
    add r13, 12

    ; ---- QNAME ----
    ; Emit labels: start a fresh label, remember its length
    ; slot, then copy characters until we hit '.' or NUL.
.start_label:
    ; Reject leading '.' and consecutive '.' — [r12] must be
    ; a real character at label start.
    movzx eax, byte [r12]
    cmp al, '.'
    je .invalid
    test al, al
    jz .invalid                     ; trailing '.' would land here too

    mov r15, r13                    ; save length byte position
    inc r13                         ; reserve one byte for length
    xor ebx, ebx                    ; label length so far

.copy_char:
    movzx eax, byte [r12]
    test al, al
    jz .end_of_name
    cmp al, '.'
    je .end_of_label
    ; Copy the character.
    mov [r13], al
    inc r13
    inc r12
    inc ebx
    cmp ebx, 63
    ja .invalid                     ; label too long
    jmp .copy_char

.end_of_label:
    ; Backfill the length byte, consume the '.', start next label.
    mov [r15], bl
    inc r12                         ; skip '.'
    jmp .start_label

.end_of_name:
    ; Backfill length byte for the final label, write the
    ; terminating zero-label.
    mov [r15], bl
    mov byte [r13], 0
    inc r13

    ; ---- QTYPE + QCLASS ----
    ; QTYPE: host-order qtype → network-order via rol.
    mov ax, r10w
    rol ax, 8
    mov [r13], ax
    mov word [r13 + 2], 0x0100      ; QCLASS = IN (net) = 00 01
    add r13, 4

    ; ---- Length + size check ----
    mov rax, r13
    sub rax, r14                    ; total bytes written
    cmp rax, 512
    ja .invalid                     ; oversize for UDP DNS

    jmp .done

.invalid:
    mov rax, -22                    ; -EINVAL

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
