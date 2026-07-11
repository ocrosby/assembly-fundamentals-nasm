; set_recv_timeout_ms(fd, ms) -> rax = 0 or -errno
;
; Bound a socket's blocking recv/read to *ms* milliseconds. When
; the timeout fires the next recv (or recvfrom / recvmsg / read)
; returns -EAGAIN (-35 macOS, -11 Linux) — the caller retries or
; treats the peer as unresponsive.
;
; Argument shape:
;   rdi = fd
;   rsi = ms (u32; the top 32 bits of rsi are ignored)
;
; Special case: ms == 0 means "blocking indefinitely" — the same
; contract libc's setsockopt(SO_RCVTIMEO, {0,0}) has on both
; platforms. To make a socket fully non-blocking on receive
; use fcntl(F_SETFL, O_NONBLOCK); this helper only bounds the
; blocking wait, not its polling shape.
;
; Argument conversion: ms → struct timeval {tv_sec, tv_usec}:
;
;   tv_sec  = ms / 1000
;   tv_usec = (ms % 1000) * 1000
;
; The kernel's struct timeval on x86_64 is 16 bytes on both
; platforms — 8-byte tv_sec plus 4-byte tv_usec on macOS
; (tail-padded to 16) or 8-byte tv_usec on Linux. Writing an
; 8-byte usec value is safe: on Linux it's the exact field
; width, on macOS the high 4 bytes fall on tail padding that
; the kernel ignores.
;
; Stack layout (24 bytes, rsp 16-aligned before setsockopt):
;   [rsp+0..7]    tv_sec
;   [rsp+8..15]   tv_usec (8-byte write; see above)
;   [rsp+16..23]  padding for alignment
;
; No registers are preserved besides those SysV requires (this
; helper does not use any callee-saved regs beyond the caller's).

%include "syscall.inc"

default rel

extern setsockopt

global set_recv_timeout_ms

section .text

set_recv_timeout_ms:
    sub rsp, 24

    ; Convert ms to (seconds, microseconds).
    mov rax, rsi                    ; ms (u64)
    xor edx, edx
    mov ecx, 1000
    div rcx                         ; rax = ms/1000, rdx = ms%1000
    mov [rsp + 0], rax              ; tv_sec
    imul rdx, 1000                  ; rdx = usec = (ms%1000) * 1000
    mov [rsp + 8], rdx              ; tv_usec

    ; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, 16)
    ; rdi already holds fd.
    mov esi, SOL_SOCKET
    mov edx, SO_RCVTIMEO
    lea rcx, [rsp]
    mov r8d, 16
    call setsockopt

    add rsp, 24
    ret
