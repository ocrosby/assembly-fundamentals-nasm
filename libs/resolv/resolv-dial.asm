; resolv_dial(name, target_port, resolver, resolver_port)
;     -> rax = connected fd, or negative errno
;
; Composed helper — the "give me a live fd for host:port" call.
; Wraps the three-step name-to-connected-socket sequence into
; a single entry point:
;
;   1. resolv_sockaddr(name, target_port, resolver, resolver_port,
;                      &sockaddr_in)  → 0 or -errno
;   2. socket(AF_INET, SOCK_STREAM, 0)  → fd or -errno
;   3. connect(fd, &sockaddr_in, 16)    → 0 or -errno
;
; On any failure the wrapper returns the first negative errno
; unchanged. If `connect` fails after `socket` succeeded, the
; wrapper closes the fd before returning the errno so callers
; do not leak file descriptors on the sad path.
;
; Arguments:
;   rdi = name*        NUL-terminated hostname
;   rsi = target_port  host order — the port to embed in
;                      sockaddr_in.sin_port
;   rdx = resolver     u32, network byte order — the DNS
;                      server's IPv4 address
;   rcx = resolver_port  host order — the DNS server's UDP
;                      port (typically 53)
;
; Return:
;   rax >= 0        a connected TCP fd, ready for read/write
;   rax  < 0        first errno seen along the chain
;                   (-ENOENT from DNS NXDOMAIN,
;                    -ECONNREFUSED from connect, etc.)
;
; Why this lives in libresolv, not libsock: libresolv already
; depends on libsock for socket / connect / close / sendto /
; recvfrom / inet_pton4. Putting resolv_dial in libsock would
; force libsock to also depend on libresolv (for
; resolv_sockaddr), producing a circular dependency. Same
; rationale as v1.7's resolv_sockaddr.
;
; Stack layout:
;   [rsp + 0..15]  the sockaddr_in scratch we fill and hand to
;                  connect
;   [rsp + 16..23] alignment padding
;
; Entry rsp is 16k+8 (post-CALL). Two pushes drop that to 16k+8
; again; sub rsp, 24 lands at 16k+0 — aligned for the nested
; call sequence.

%include "syscall.inc"

default rel

extern resolv_sockaddr
extern socket, connect, close      ; libsock

global resolv_dial

section .text

%define AF_INET      2
%define SOCK_STREAM  1

resolv_dial:
    push r12
    push r13
    sub rsp, 24                     ; 16-byte sockaddr + 8 padding

    ; ---- resolv_sockaddr(name, target_port, resolver, resolver_port, &sockaddr) ----
    ; The first four args are already in their SysV slots
    ; (rdi/rsi/rdx/rcx). Only r8 needs setting.
    lea r8, [rsp]
    call resolv_sockaddr
    test rax, rax
    js .done                        ; propagate -errno unchanged

    ; ---- socket(AF_INET, SOCK_STREAM, 0) ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx                    ; protocol = 0 (default: TCP)
    call socket
    test rax, rax
    js .done
    mov r12d, eax                   ; save connected-side fd

    ; ---- connect(fd, &sockaddr_in, 16) ----
    mov edi, r12d
    lea rsi, [rsp]
    mov edx, 16
    call connect
    test rax, rax
    js .connect_failed

    ; Success — return the fd we just wired up.
    mov eax, r12d

.done:
    add rsp, 24
    pop r13
    pop r12
    ret

.connect_failed:
    ; Preserve the errno across close so the caller sees the
    ; connect-side error, not the close-side one.
    mov r13, rax
    mov edi, r12d
    call close
    mov rax, r13
    jmp .done
