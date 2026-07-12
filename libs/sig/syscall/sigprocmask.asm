; sigprocmask(how: rdi, set: rsi, oldset: rdx) -> 0 or -errno
;
; Change the calling thread's signal mask. `how` is one of
; SIG_BLOCK (add the signals in `set` to the mask), SIG_UNBLOCK
; (remove them), or SIG_SETMASK (replace the mask with `set`).
;
; If `set` is NULL, the mask is not changed — the syscall
; degenerates into a "read the current mask" call. In that
; case pass `how = 0` (any value is fine; the kernel ignores
; it when set is NULL, but avoid uninitialized junk).
;
; If `oldset` is NULL, the previous mask is not written back.
;
; Both `set` and `oldset` point at a sigset buffer that must
; be at least SIGSET_BYTES wide (4 on macOS, 8 on Linux — see
; syscall.inc). Callers reserving `resb SIGSET_BYTES` in
; .bss get portable buffers.
;
; Linux's `rt_sigprocmask(2)` takes a 4th argument,
; `sigsetsize`, that must equal `_NSIG/8 = 8`. macOS's BSD
; sigprocmask (syscall 48) is a 3-arg call; the wrapper
; injects the 4th arg on Linux and leaves rcx untouched on
; macOS.

%include "syscall.inc"

default rel

global sigprocmask

section .text

sigprocmask:
    mov rax, SYS_sigprocmask
%ifndef MACOS
    ; Linux: sigsetsize = 8 in the syscall's 4th slot (r10).
    ; The 4th SysV C arg is rcx; SYSCALL_ARG4 shuffles it to
    ; r10 for us, but we are supplying the constant directly.
    mov r10, SIGSET_BYTES
%endif
    SYSCALL_NORM
    ret
