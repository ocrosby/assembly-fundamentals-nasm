; sigsuspend(mask: rdi) -> -EINTR (or other negative errno)
;
; Blocks until a signal not in `*mask` is delivered to the
; caller. On delivery the handler (if any) runs and then
; `sigsuspend` returns `-EINTR`. `sigsuspend` never returns a
; non-negative value on success — this is the one wrapper in
; libsig whose contract is "negative on `success`."
;
; Semantics: while the call blocks, the process's signal mask
; is temporarily replaced with `*mask`. When a signal outside
; that mask is delivered, the original mask is restored before
; the wrapper returns. Callers use this to atomically unblock
; a signal and wait for it — the sigprocmask + wait pattern
; alone has a race where the signal can arrive between the
; unblock and the wait.
;
; Platform ABIs diverge:
;
; - **macOS BSD sigsuspend** (syscall 111) takes the
;   sigset_t **by value** in `edi` (a 32-bit mask). The
;   wrapper dereferences the caller's pointer and loads the
;   4-byte mask into edi before issuing the syscall.
; - **Linux rt_sigsuspend** (syscall 130) takes a pointer to
;   the sigset_t in `rdi` plus `sigsetsize` in `rsi`
;   (`_NSIG/8 = 8`). The wrapper leaves `rdi` alone and
;   injects `sigsetsize`.
;
; Callers pass a pointer either way — the POSIX shape — and
; libsig normalizes the calling convention internally.

%include "syscall.inc"

default rel

global sigsuspend

section .text

sigsuspend:
%ifdef MACOS
    ; Darwin wants the mask value in edi. Deref the caller's
    ; sigset_t pointer to load the low 4 bytes.
    mov edi, [rdi]
%else
    ; Linux wants the pointer in rdi (already there) plus
    ; sigsetsize in rsi.
    mov rsi, SIGSET_BYTES
%endif
    mov rax, SYS_sigsuspend
    SYSCALL_NORM
    ret
