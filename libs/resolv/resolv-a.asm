; resolv_a(name: rdi, resolver: rsi, port: rdx, out_ip: rcx)
;     -> rax = 0 or negative errno
;
; Resolves the A record for *name* by querying *resolver:port*
; over UDP and writes the resulting four-byte IPv4 address (in
; network byte order) to *out_ip*.
;
; Arguments:
;   name      — NUL-terminated hostname string
;   resolver  — u32 IPv4 in network byte order (0x0808_0808 for
;               8.8.8.8, since 8.8.8.8's four octets on the wire
;               are 08 08 08 08 regardless of host endianness)
;   port      — resolver port in host order (typically 53; the
;               test harness passes an ephemeral port assigned
;               by the mock server)
;   out_ip    — 4-byte output buffer
;
; Return convention: 0 on success; negative errno on failure.
; The specific mappings match wire-decode's:
;
;   -EINVAL   (-22)  — malformed name (empty / too-long label)
;   -ENOENT   (-2)   — NXDOMAIN
;   -EIO      (-5)   — SERVFAIL / unrecognized RCODE
;   -ENODATA  (-96 macOS, -61 Linux) — no A/IN answer
;   -EBADMSG  (-74)  — malformed wire response
;   -ETIMEDOUT (-60 macOS, -110 Linux) — recvfrom timed out
;   any negative errno from socket(), sendto(), recvfrom(),
;   close() — propagated through unchanged
;
; Sequence:
;   1  resolv_random(id_buf, 2)                  → 0 or -errno
;   2  resolv_encode_query(name, id, query_buf)  → len or -EINVAL
;   3  socket(AF_INET, SOCK_DGRAM, 0)             → fd or -errno
;   4  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv)
;   5  build sockaddr_in for (resolver, 53)
;   6  sendto(fd, query_buf, len, 0, &sa, 16)     → n or -errno
;   7  recvfrom(fd, resp_buf, 512, 0, NULL, NULL) → n or -errno
;   8  resolv_decode_response(resp_buf, n, id, out_ip) → 0 or -errno
;   9  close(fd)  (result ignored — success/failure already known)
;
; Every failure between step 3 and step 9 closes the fd before
; returning so callers do not have to clean up.

%include "syscall.inc"

default rel

extern resolv_random, resolv_encode_query, resolv_decode_response
extern socket, setsockopt, sendto, recvfrom, close

global resolv_a

section .text

%define AF_INET       2
%define SOCK_DGRAM    2
%define QUERY_MAX     512

%ifdef MACOS
%define SIN_HEADER    0x0210        ; sin_len=16 << 0 | AF_INET << 8, little-endian u16
%define SOL_SOCKET    0xffff
%define SO_RCVTIMEO   0x1006
%else
%define SIN_HEADER    0x0002        ; sin_family = AF_INET
%define SOL_SOCKET    1
%define SO_RCVTIMEO   20
%endif

; Register roles inside the function (across the whole flow):
;   r12 = fd (once socket succeeds)
;   r13 = out_ip (survives all calls)
;   r14 = query length (from encode)
;   r15 = query id (u16 host order)
;   rbx = last saved errno for close-then-return path

; Stack layout after the initial pushes + sub:
;
;   [rsp+0 .. rsp+2]      id_buf   (2 bytes)
;   [rsp+16 .. rsp+32]    sockaddr_in (16 bytes)
;   [rsp+32 .. rsp+48]    struct timeval (sec, usec)
;   [rsp+48 .. rsp+560]   query buffer (512 bytes)
;   [rsp+560 .. rsp+1072] response buffer (512 bytes)
;   total stack: 1072 bytes (aligned to 16)

%define ID_OFF     0
%define SA_OFF     16
%define TV_OFF     32
%define QUERY_OFF  48
%define RESP_OFF   560
%define STACK_SIZE 1072

resolv_a:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, STACK_SIZE

    mov r13, rcx                    ; out_ip
    ; Save the name, resolver IP, and port into scratch slots
    ; on the stack so they survive our internal calls. The id
    ; slot lives in the first two bytes at [rsp + ID_OFF]; the
    ; four bytes after it are unused, so we reuse them.
    mov [rsp + ID_OFF + 4], rdi     ; scratch spill: name
    mov [rsp + ID_OFF + 12], rsi    ; scratch spill: resolver
    ; Convert port from host to network order once and store.
    ; rdx holds the port as u16 host order; rol swaps the two
    ; low bytes, and we save the resulting network-order u16.
    mov ax, dx
    rol ax, 8
    mov [rsp + ID_OFF + 24], ax     ; scratch spill: port (net order)

    ; ---- 1: resolv_random(id_buf, 2) ----
    lea rdi, [rsp + ID_OFF]
    mov esi, 2
    call resolv_random
    test rax, rax
    js .early_fail

    ; Read the two random bytes as a host-order u16 (we treat
    ; them as opaque bits — endianness only matters at wire
    ; encode time, and encode swaps).
    movzx r15d, word [rsp + ID_OFF]

    ; ---- 2: resolv_encode_query(name, id, query_buf) ----
    mov rdi, [rsp + ID_OFF + 4]     ; name
    mov rsi, r15                    ; id
    lea rdx, [rsp + QUERY_OFF]
    call resolv_encode_query
    test rax, rax
    js .early_fail
    mov r14, rax                    ; query length

    ; ---- 3: socket(AF_INET, SOCK_DGRAM, 0) ----
    mov edi, AF_INET
    mov esi, SOCK_DGRAM
    xor edx, edx
    call socket
    test rax, rax
    js .early_fail
    mov r12, rax                    ; fd

    ; ---- 4: setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, 16) ----
    ; timeval { tv_sec = 5, tv_usec = 0 } — 5-second read timeout.
    mov qword [rsp + TV_OFF], 5
    mov qword [rsp + TV_OFF + 8], 0
    mov rdi, r12
    mov esi, SOL_SOCKET
    mov edx, SO_RCVTIMEO
    lea rcx, [rsp + TV_OFF]
    mov r8d, 16
    call setsockopt
    test rax, rax
    js .close_and_fail

    ; ---- 5: sockaddr_in for (resolver, port) ----
    mov word [rsp + SA_OFF], SIN_HEADER
    mov ax, [rsp + ID_OFF + 24]     ; port (net order, from spill)
    mov [rsp + SA_OFF + 2], ax
    mov rax, [rsp + ID_OFF + 12]    ; resolver
    mov [rsp + SA_OFF + 4], eax     ; sin_addr (already net order)
    mov qword [rsp + SA_OFF + 8], 0 ; sin_zero

    ; ---- 6: sendto(fd, query, len, 0, &sa, 16) ----
    mov rdi, r12
    lea rsi, [rsp + QUERY_OFF]
    mov rdx, r14
    xor ecx, ecx
    lea r8, [rsp + SA_OFF]
    mov r9d, 16
    call sendto
    test rax, rax
    js .close_and_fail

    ; ---- 7: recvfrom(fd, resp, 512, 0, NULL, NULL) ----
    mov rdi, r12
    lea rsi, [rsp + RESP_OFF]
    mov edx, QUERY_MAX
    xor ecx, ecx
    xor r8, r8
    xor r9, r9
    call recvfrom
    test rax, rax
    js .close_and_fail
    mov rbx, rax                    ; response length (for decode)

    ; ---- 8: decode ----
    lea rdi, [rsp + RESP_OFF]
    mov rsi, rbx
    mov rdx, r15                    ; expected_id
    mov rcx, r13                    ; out_ip
    call resolv_decode_response
    mov rbx, rax                    ; save decode result

    ; ---- 9: close(fd), ignoring its return ----
    mov rdi, r12
    call close
    mov rax, rbx                    ; return decoder's verdict
    jmp .done

.close_and_fail:
    ; A syscall along the transport chain failed. Preserve its
    ; errno while we close the fd.
    mov rbx, rax
    mov rdi, r12
    call close
    mov rax, rbx
    jmp .done

.early_fail:
    ; Failure happened before socket() succeeded; nothing to
    ; close. rax already holds the negative errno.
.done:
    add rsp, STACK_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
