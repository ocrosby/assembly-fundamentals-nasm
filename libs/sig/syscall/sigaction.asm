; sigaction(signum: rdi, act: rsi, oldact: rdx) -> 0 or -errno
;
; Install a disposition for `signum`. `act` points at a
; struct sigaction laid out per `syscall.inc`'s
; SA_HANDLER_OFF / SA_MASK_OFF / SA_FLAGS_OFF constants
; (SIGACTION_SIZE bytes total — 24 on macOS, 32 on Linux).
; If `act` is NULL, the current disposition is left alone.
; If `oldact` is non-NULL, the previous disposition is
; written back through it.
;
; The struct layouts differ per platform. Callers who need
; to build one at runtime look at the offsets in
; `syscall.inc` and use `resb SIGACTION_SIZE` to reserve
; the buffer.
;
; v1.2 scope: `sa_handler` must be either `SIG_DFL` (0) or
; `SIG_IGN` (1). Installing a real handler function
; requires a SA_RESTORER trampoline on Linux and an
; sa_tramp trampoline on macOS — both deferred to v1.3.
; The wrapper itself does not validate the handler value;
; it happily passes any pointer to the kernel. Callers
; who install a real handler in v1.2 will find that the
; process crashes when the handler returns (Linux) or that
; the kernel calls a NULL sa_tramp (macOS).
;
; Linux's rt_sigaction takes a 4th argument, `sigsetsize`,
; that must equal `_NSIG/8 = 8`. macOS sigaction (syscall
; 46) is a 3-arg call. The wrapper injects the 4th arg on
; Linux and leaves rcx untouched on macOS.

%include "syscall.inc"

default rel

global sigaction

section .text

sigaction:
    mov rax, SYS_sigaction
%ifndef MACOS
    ; Linux: sigsetsize = 8 in the syscall's 4th slot (r10).
    mov r10, SIGSET_BYTES
%endif
    SYSCALL_NORM
    ret
