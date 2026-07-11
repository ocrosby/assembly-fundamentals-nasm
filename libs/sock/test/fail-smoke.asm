; fail-smoke.asm — exercise the failure branch of every libsock
; syscall wrapper.
;
; The three positive-path tests (ipc-smoke, server-smoke,
; tcp-smoke) only hit the "success" arm of the SYSCALL_NORM
; macro: on macOS the wrapper is
;
;   syscall
;   jnc .ok            ; success — carry clear
;   neg rax            ; failure — normalize positive errno to -errno
;  .ok:
;
; A success-only run never executes the `neg rax` line. This
; test forces every wrapper into the failure branch with args
; the kernel is guaranteed to reject (bogus fd, invalid address
; family, NULL pointer where one is required), then verifies
; rax comes back negative. If a wrapper returned a positive
; errno instead of a negative one, we would catch it here.
;
; On Linux the macro is just `syscall` (the kernel already
; puts -errno in rax); this test also verifies each wrapper
; propagates that negative value correctly on Linux.
;
; Prints "PASS\n" and exits 0 when every sub-check returned a
; negative value. Prints "FAIL:<id>\n" to stderr and exits 1 on
; the first wrapper that returned a non-negative value from a
; call that should have failed. Sub-check ids match the
; wrapper being tested:
;
;   0 socket       1 bind         2 listen      3 accept
;   4 connect      5 shutdown     6 close       7 read
;   8 write        9 send         A recv        B sendto
;   C recvfrom    D sendmsg       E recvmsg     F getsockopt
;   G setsockopt  H getsockname   I getpeername J socketpair
;   K select      L poll
;
; Design notes:
;
;   * "Bogus fd" is 999999 — well outside any process's fd
;     table. The kernel checks fd validity before any pointer
;     dereferences, so we can safely pass real pointers for the
;     other args without worrying about EFAULT masking EBADF.
;   * socket() and socketpair() don't take an fd, so we force
;     failure via an invalid domain (99 is unassigned).
;   * poll() ignores negative fds inside pollfd entries, so we
;     pass NULL for the fds array with nfds=1 — the kernel
;     reads past NULL and returns EFAULT.
;   * select() with an invalid fd bit set in the read fd_set
;     returns EBADF once the kernel walks the set.

%define AF_UNIX 1
%define SOCK_STREAM 1
%define BAD_FD  999999
%define BAD_AF  99                    ; unassigned address family

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern socket, bind, listen, accept, connect, shutdown, close
extern read, write, send, recv, sendto, recvfrom, sendmsg, recvmsg
extern getsockopt, setsockopt, getsockname, getpeername, socketpair
extern select, poll

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id  equ fail_msg + 5
fail_len equ $ - fail_msg

section .bss
buf:      resb 64                    ; catch-all buffer for pointers
lenbuf:   resd 1                     ; socklen_t in/out slot
fdset:    resb 128                   ; fd_set with the invalid bit set
sv:       resd 2                     ; socketpair output buffer
mh:       resb 64                    ; msghdr scratch
tv:       resb 16                    ; struct timeval — zeroed = poll

section .text

; Every sub-check follows the same shape: preset the fail id,
; make the call, jump to .fail if rax >= 0. Using a macro keeps
; the block short and highlights the actual argument setup.
%macro EXPECT_NEGATIVE 1
    mov byte [fail_id], %1
    test rax, rax
    jns .fail
%endmacro

_start:
_main:
    mov dword [lenbuf], 16

    ; 0: socket(BAD_AF, SOCK_STREAM, 0) -> -EAFNOSUPPORT
    mov edi, BAD_AF
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    EXPECT_NEGATIVE '0'

    ; 1: bind(BAD_FD, buf, 16) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 16
    call bind
    EXPECT_NEGATIVE '1'

    ; 2: listen(BAD_FD, 1) -> -EBADF
    mov edi, BAD_FD
    mov esi, 1
    call listen
    EXPECT_NEGATIVE '2'

    ; 3: accept(BAD_FD, buf, &lenbuf) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    lea rdx, [lenbuf]
    call accept
    EXPECT_NEGATIVE '3'

    ; 4: connect(BAD_FD, buf, 16) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 16
    call connect
    EXPECT_NEGATIVE '4'

    ; 5: shutdown(BAD_FD, 0) -> -EBADF
    mov edi, BAD_FD
    xor esi, esi
    call shutdown
    EXPECT_NEGATIVE '5'

    ; 6: close(BAD_FD) -> -EBADF
    mov edi, BAD_FD
    call close
    EXPECT_NEGATIVE '6'

    ; 7: read(BAD_FD, buf, 1) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    call read
    EXPECT_NEGATIVE '7'

    ; 8: write(BAD_FD, buf, 1) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    call write
    EXPECT_NEGATIVE '8'

    ; 9: send(BAD_FD, buf, 1, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    call send
    EXPECT_NEGATIVE '9'

    ; A: recv(BAD_FD, buf, 1, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    call recv
    EXPECT_NEGATIVE 'A'

    ; B: sendto(BAD_FD, buf, 1, 0, NULL, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    xor r8, r8
    xor r9, r9
    call sendto
    EXPECT_NEGATIVE 'B'

    ; C: recvfrom(BAD_FD, buf, 1, 0, NULL, NULL) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    mov edx, 1
    xor ecx, ecx
    xor r8, r8
    xor r9, r9
    call recvfrom
    EXPECT_NEGATIVE 'C'

    ; D: sendmsg(BAD_FD, mh, 0) -> -EBADF
    ; mh is zeroed by .bss init — fd check runs before struct
    ; validation, so any zero-inited msghdr suffices.
    mov edi, BAD_FD
    lea rsi, [mh]
    xor edx, edx
    call sendmsg
    EXPECT_NEGATIVE 'D'

    ; E: recvmsg(BAD_FD, mh, 0) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [mh]
    xor edx, edx
    call recvmsg
    EXPECT_NEGATIVE 'E'

    ; F: getsockopt(BAD_FD, 0, 0, buf, &lenbuf) -> -EBADF
    mov edi, BAD_FD
    xor esi, esi
    xor edx, edx
    lea rcx, [buf]
    lea r8, [lenbuf]
    call getsockopt
    EXPECT_NEGATIVE 'F'

    ; G: setsockopt(BAD_FD, 0, 0, buf, 4) -> -EBADF
    mov edi, BAD_FD
    xor esi, esi
    xor edx, edx
    lea rcx, [buf]
    mov r8d, 4
    call setsockopt
    EXPECT_NEGATIVE 'G'

    ; H: getsockname(BAD_FD, buf, &lenbuf) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    lea rdx, [lenbuf]
    call getsockname
    EXPECT_NEGATIVE 'H'

    ; I: getpeername(BAD_FD, buf, &lenbuf) -> -EBADF
    mov edi, BAD_FD
    lea rsi, [buf]
    lea rdx, [lenbuf]
    call getpeername
    EXPECT_NEGATIVE 'I'

    ; J: socketpair(BAD_AF, SOCK_STREAM, 0, sv) -> -EAFNOSUPPORT
    mov edi, BAD_AF
    mov esi, SOCK_STREAM
    xor edx, edx
    lea rcx, [sv]
    call socketpair
    EXPECT_NEGATIVE 'J'

    ; K: select() with negative nfds -> -EINVAL. macOS's zero-
    ; timeout select() short-circuits fd-set validation, so an
    ; invalid-bit-in-fdset trick doesn't force a failure there;
    ; a negative nfds does on both platforms.
    mov edi, -1                      ; nfds = -1 -> -EINVAL
    xor esi, esi                     ; readfds = NULL
    xor edx, edx                     ; writefds = NULL
    xor ecx, ecx                     ; exceptfds = NULL
    xor r8, r8                       ; timeout = NULL
    call select
    EXPECT_NEGATIVE 'K'

    ; L: poll(NULL, 1, 0) -> -EFAULT
    xor edi, edi                     ; fds = NULL
    mov esi, 1                       ; nfds = 1
    xor edx, edx                     ; timeout = 0
    call poll
    EXPECT_NEGATIVE 'L'

    ; PASS
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
