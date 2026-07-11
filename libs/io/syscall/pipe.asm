; pipe(pipefd*) -> rax = 0 or -errno
;
; Create a unidirectional data channel. On success writes two
; new fds into pipefd[0] (read end) and pipefd[1] (write end):
;
;   * pipefd[0]  read-only, receives whatever the write end
;                sends. Reading from an empty pipe blocks until
;                data arrives OR every write end is closed
;                (which returns 0 as EOF).
;   * pipefd[1]  write-only, sends bytes to the read end.
;                Writing to a pipe with no reader raises
;                SIGPIPE (default terminates the process) and
;                the write returns -EPIPE.
;
; Data is a byte stream — writes and reads do not preserve
; message boundaries. For record-oriented plumbing use a UNIX
; socket pair via libsock's socketpair.
;
; Cross-platform ABI note. Linux's `pipe` syscall (SYS 22) is
; conventional — it writes both fds into the caller's int[2]
; and returns 0 or -errno. macOS's `pipe` syscall (BSD 42)
; instead returns the two fds directly in `rax` (read end)
; and `rdx` (write end), with the carry flag indicating error
; the usual way. libio's wrapper hides this: on macOS we save
; the caller's array pointer, run the syscall, and if it
; succeeds fan the two register values back into the array
; the caller passed in — matching Linux's contract exactly.

%include "syscall.inc"

default rel

global pipe

section .text

pipe:
%ifdef MACOS
    ; Save the caller's array pointer (r10 is caller-saved and
    ; not touched by the syscall's ABI) so we can spread the
    ; two returned fds back into it after the call.
    mov r10, rdi
    mov rax, SYS_pipe
    syscall
    jnc .macos_ok
    ; Error path: normalize carry-set errno the way SYSCALL_NORM
    ; would. rax already contains +errno; negate for the shared
    ; -errno contract.
    neg rax
    ret
.macos_ok:
    ; rax = read end, rdx = write end (Darwin BSD ABI).
    mov [r10], eax                  ; pipefd[0] = read
    mov [r10 + 4], edx              ; pipefd[1] = write
    xor eax, eax                    ; return 0
    ret
%else
    ; Linux pipe(int pipefd[2]) writes both fds into rdi's
    ; buffer and returns 0 or -errno itself. Nothing for us
    ; to fix up.
    mov rax, SYS_pipe
    SYSCALL_NORM
    ret
%endif
