; resolv_sockaddr(name, target_port, resolver, resolver_port, sockaddr_in_out)
;     -> rax = 0 or negative errno
;
; Composed helper that turns a hostname + port into a fully
; populated `struct sockaddr_in`, ready to hand to `connect()`
; or `sendto()`. The resolver-side arguments (which DNS server
; to query, on which UDP port) mirror `resolv_a`'s signature so
; callers already wired for DNS need only extend the argument
; list by one field — the output sockaddr.
;
; Arguments:
;   rdi = name*      NUL-terminated hostname
;   rsi = target_port  the port to embed in the returned
;                    sockaddr_in.sin_port. Host order — the
;                    helper htons-swaps it before storing.
;   rdx = resolver   u32, network byte order — the DNS
;                    server's IPv4 address
;   rcx = resolver_port  host order — the DNS server's UDP
;                    port (typically 53)
;   r8  = sockaddr_in_out*  caller-allocated 16-byte struct
;                    sockaddr_in; overwritten entirely on
;                    success.
;
; Return:
;   rax = 0          success; *sockaddr_in_out is populated:
;                       +0: sin_family / sin_len (per platform)
;                       +2: sin_port  (network order)
;                       +4: sin_addr  (network order, from DNS)
;                       +8: sin_zero  (zeroed)
;   rax = -errno     any error from resolv_a is passed through
;                    unchanged; *sockaddr_in_out is left in an
;                    unspecified state.
;
; Why this lives in libresolv, not libsock: the actual DNS work
; is `resolv_a`, which already links against libsock. Putting
; the composed helper in libsock would force libsock to link
; against libresolv, creating a circular dependency (libresolv
; already depends on libsock).

%include "syscall.inc"

default rel

extern resolv_a

global resolv_sockaddr

section .text

resolv_sockaddr:
    ; Preserve target_port and sockaddr_in_out across the
    ; resolv_a call (both are caller-saved in SysV; we need
    ; them after the call returns).
    push r12
    push r13
    sub rsp, 8                      ; align rsp to 16 before call

    mov r12, rsi                    ; target_port
    mov r13, r8                     ; sockaddr_in_out

    ; resolv_a(name, resolver, resolver_port, out_ip)
    ; Reshuffle args:  rdi already has name,
    ;   rsi ← rdx (resolver), rdx ← rcx (resolver_port),
    ;   rcx ← &sockaddr_in_out.sin_addr = r13 + 4
    mov rsi, rdx
    mov rdx, rcx
    lea rcx, [r13 + 4]
    call resolv_a

    test rax, rax
    js .done                        ; -errno propagates unchanged

    ; ---- Populate the rest of the sockaddr ----
    ; sin_family / sin_len (offset 0). macOS carries a leading
    ; sin_len byte; both platforms collapse the leading two
    ; bytes into a single word.
%ifdef MACOS
    mov word [r13], 0x0210          ; sin_len=16, sin_family=AF_INET (2)
%else
    mov word [r13], 0x0002          ; sin_family=AF_INET (u16)
%endif

    ; sin_port (offset 2) — htons(target_port). The low 16 bits
    ; of r12 hold the caller's host-order port; a single
    ; byte-swap (xchg al, ah) turns it into network order.
    mov eax, r12d
    xchg al, ah                     ; htons
    mov [r13 + 2], ax

    ; sin_zero (offset 8) — 8 bytes of zero padding.
    xor eax, eax
    mov [r13 + 8], rax

    xor eax, eax                    ; success

.done:
    add rsp, 8
    pop r13
    pop r12
    ret
