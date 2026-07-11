; ipc-smoke.asm — socketpair-based smoke test covering the
; remaining I/O and multiplexing wrappers.
;
; Creates an AF_UNIX SOCK_STREAM pair via socketpair(), then
; exercises nine libsock wrappers against that pair without
; needing a Python peer (the two fds talk to each other in the
; same process):
;
;   * send / recv on a connected socket
;   * sendto / recvfrom with NULL address (matches connected send)
;   * sendmsg / recvmsg with a single-iovec msghdr (msg_iovlen
;     size differs between Darwin and Linux — Darwin uses int
;     at offset 24, Linux uses size_t at 24..32; see MSGHDR_*
;     macros below)
;   * select and poll to observe read-readiness after a write
;
; Plus close for both ends. Prints "PASS\n" and exits 0 when
; every sub-check passes; prints "FAIL:<id>\n" to stderr and
; exits 1 on the first failure. Sub-check ids:
;
;   0 socketpair()
;   1 send() bytes-sent count
;   2 recv() bytes-received count
;   3 recv() delivered the same payload
;   4 sendto(NULL) bytes-sent count
;   5 recvfrom(NULL) bytes-received count
;   6 recvfrom(NULL) delivered the same payload
;   7 sendmsg() bytes-sent count
;   8 recvmsg() bytes-received count
;   9 recvmsg() delivered the same payload
;   A select() reported read-ready
;   B recv drained the select marker byte
;   C poll() reported POLLIN
;   D recv drained the poll marker byte
;   E close(sv[0])
;   F close(sv[1])

%define AF_UNIX     1
%define SOCK_STREAM 1
%define POLLIN      1

%ifdef MACOS
%define SYS_write   0x2000004
%define SYS_exit    0x2000001
; Darwin msghdr layout (48 bytes total):
;   0..8    msg_name (void*)
;   8..12   msg_namelen (socklen_t = u32)
;   12..16  padding
;   16..24  msg_iov (struct iovec*)
;   24..28  msg_iovlen (int on Darwin)
;   28..32  padding
;   32..40  msg_control (void*)
;   40..44  msg_controllen (socklen_t)
;   44..48  msg_flags (int)
%define MSG_IOVLEN_SIZE 4
%define MSG_FLAGS_OFF   44
%else
%define SYS_write   1
%define SYS_exit    60
; Linux msghdr layout (56 bytes total):
;   0..8    msg_name
;   8..12   msg_namelen
;   12..16  padding
;   16..24  msg_iov
;   24..32  msg_iovlen (size_t on Linux)
;   32..40  msg_control
;   40..48  msg_controllen (size_t)
;   48..52  msg_flags
;   52..56  padding
%define MSG_IOVLEN_SIZE 8
%define MSG_FLAGS_OFF   48
%endif

default rel

extern socketpair, send, recv, sendto, recvfrom, sendmsg, recvmsg
extern select, poll, close

global _start
global _main

section .rodata
send_payload:    db "SEND"
sto_payload:     db "STO_"
smsg_payload:    db "SMSG"
sel_byte:        db "S"
poll_byte:       db "P"

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

; The fail message lives in .data because we overwrite the '?'
; slot with a sub-check id at runtime. On Mach-O 64, .rodata is
; strictly read-only — writing to it there raises SIGBUS.
section .data
fail_msg: db "FAIL:?", 10
fail_id  equ fail_msg + 5
fail_len equ $ - fail_msg

section .bss
sv:       resd 2                    ; socketpair-returned fds
buf:      resb 64                   ; general receive buffer
mh:       resb 64                   ; msghdr scratch (max 56 bytes needed)
iov:      resb 16                   ; struct iovec { void*, size_t }
fdset:    resb 128                  ; fd_set (1024 bits)
tv:       resb 16                   ; struct timeval { time_t, long }
pfd:      resb 8                    ; struct pollfd { int, short, short }

section .text

_start:
_main:
    ; ---- 0: socketpair(AF_UNIX, SOCK_STREAM, 0, sv) ----
    mov byte [fail_id], '0'
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM
    xor edx, edx
    lea rcx, [sv]
    call socketpair
    test rax, rax
    js .fail
    mov r12d, [sv]                   ; sv[0]
    mov r13d, [sv + 4]               ; sv[1]

    ; ---- 1-3: send / recv ----
    mov byte [fail_id], '1'
    mov edi, r12d
    lea rsi, [send_payload]
    mov edx, 4
    xor ecx, ecx
    call send
    cmp rax, 4
    jne .fail

    mov byte [fail_id], '2'
    mov edi, r13d
    lea rsi, [buf]
    mov edx, 64
    xor ecx, ecx
    call recv
    cmp rax, 4
    jne .fail

    mov byte [fail_id], '3'
    mov eax, [rel send_payload]
    cmp eax, dword [buf]
    jne .fail

    ; ---- 4-6: sendto (NULL addr) / recvfrom (NULL addr) ----
    mov byte [fail_id], '4'
    mov edi, r12d
    lea rsi, [sto_payload]
    mov edx, 4
    xor ecx, ecx
    xor r8, r8
    xor r9, r9
    call sendto
    cmp rax, 4
    jne .fail

    mov byte [fail_id], '5'
    mov edi, r13d
    lea rsi, [buf]
    mov edx, 64
    xor ecx, ecx
    xor r8, r8
    xor r9, r9
    call recvfrom
    cmp rax, 4
    jne .fail

    mov byte [fail_id], '6'
    mov eax, [rel sto_payload]
    cmp eax, dword [buf]
    jne .fail

    ; ---- 7-9: sendmsg / recvmsg ----
    ; Zero the whole msghdr scratch — 64 bytes covers both layouts.
    lea rdi, [mh]
    xor eax, eax
    mov ecx, 8
    rep stosq

    ; iovec { iov_base = smsg_payload, iov_len = 4 }
    lea rax, [smsg_payload]
    mov [iov], rax
    mov qword [iov + 8], 4

    ; msghdr { msg_iov = &iov; msg_iovlen = 1; everything else NULL/0 }
    lea rax, [iov]
    mov [mh + 16], rax
%if MSG_IOVLEN_SIZE == 4
    mov dword [mh + 24], 1
%else
    mov qword [mh + 24], 1
%endif

    mov byte [fail_id], '7'
    mov edi, r12d
    lea rsi, [mh]
    xor edx, edx
    call sendmsg
    cmp rax, 4
    jne .fail

    ; Re-point iov_base at buf for recvmsg; msg_iov itself still
    ; points at iov, so we only need to update the iovec.
    lea rax, [buf]
    mov [iov], rax
    mov qword [iov + 8], 64

    mov byte [fail_id], '8'
    mov edi, r13d
    lea rsi, [mh]
    xor edx, edx
    call recvmsg
    cmp rax, 4
    jne .fail

    mov byte [fail_id], '9'
    mov eax, [rel smsg_payload]
    cmp eax, dword [buf]
    jne .fail

    ; ---- A-B: select() ----
    ; Push one marker byte into sv[0] so sv[1] becomes readable.
    mov edi, r12d
    lea rsi, [sel_byte]
    mov edx, 1
    xor ecx, ecx
    call send

    ; Zero fdset, then set bit for sv[1].
    lea rdi, [fdset]
    xor eax, eax
    mov ecx, 16
    rep stosq

    ; mask = 1 << (fd % 8);  byte_index = fd / 8
    mov ecx, r13d
    and ecx, 7
    mov eax, 1
    shl eax, cl
    mov edx, r13d
    shr edx, 3
    lea rdi, [fdset]
    or byte [rdi + rdx], al

    ; timeval: 1-second timeout so a slow CI runner doesn't
    ; misreport a spurious "not ready".
    mov qword [tv], 1
    mov qword [tv + 8], 0

    mov byte [fail_id], 'A'
    mov edi, r13d
    inc edi                          ; nfds = max_fd + 1
    lea rsi, [fdset]
    xor edx, edx                     ; writefds = NULL
    xor ecx, ecx                     ; exceptfds = NULL
    lea r8, [tv]
    call select
    cmp rax, 1
    jne .fail

    mov byte [fail_id], 'B'
    mov edi, r13d
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    call recv
    cmp rax, 1
    jne .fail
    cmp byte [buf], 'S'
    jne .fail

    ; ---- C-D: poll() ----
    mov edi, r12d
    lea rsi, [poll_byte]
    mov edx, 1
    xor ecx, ecx
    call send

    mov [pfd], r13d                  ; pollfd.fd
    mov word [pfd + 4], POLLIN       ; pollfd.events
    mov word [pfd + 6], 0            ; pollfd.revents

    mov byte [fail_id], 'C'
    lea rdi, [pfd]
    mov esi, 1                       ; nfds
    mov edx, 1000                    ; 1s timeout in ms
    call poll
    cmp rax, 1
    jne .fail

    mov byte [fail_id], 'D'
    mov edi, r13d
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    call recv
    cmp rax, 1
    jne .fail
    cmp byte [buf], 'P'
    jne .fail

    ; ---- E-F: close both fds ----
    mov byte [fail_id], 'E'
    mov edi, r12d
    call close
    test rax, rax
    jnz .fail

    mov byte [fail_id], 'F'
    mov edi, r13d
    call close
    test rax, rax
    jnz .fail

    ; --- PASS ---
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall
