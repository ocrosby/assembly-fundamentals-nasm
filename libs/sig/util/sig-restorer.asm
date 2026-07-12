; sig_restorer — Linux SA_RESTORER trampoline (v1.3)
;
; Linux's `rt_sigaction` accepts a userspace stub called
; `sa_restorer` that the kernel jumps to when the signal
; handler `ret`s. Its only job is to invoke
; `SYS_rt_sigreturn`, which unwinds the signal frame the
; kernel stacked on delivery and resumes the interrupted
; instruction. Without it, the handler's `ret` pops garbage
; and the process crashes.
;
; Callers who install a custom handler set:
;
;     act.sa_flags     |= SA_RESTORER
;     act.sa_restorer   = sig_restorer
;
; The kernel checks the SA_RESTORER bit at sigaction install
; time and remembers to use sa_restorer on delivery.
;
; This stub is macOS-inert — the file conditionally compiles
; nothing when %ifdef MACOS. macOS callers use `sig_tramp`
; instead (see util/sig-tramp.asm).
;
; The trampoline does not return normally: SYS_rt_sigreturn
; overwrites `rsp` and `rip` from the saved signal frame.
; The `ret` at the bottom is defensive — if for some reason
; the syscall returns to userspace, the stray return path
; falls through cleanly rather than executing whatever
; follows in .text.

%include "syscall.inc"

%ifndef MACOS

default rel

global sig_restorer

section .text

sig_restorer:
    mov rax, SYS_rt_sigreturn
    syscall
    ret                             ; unreachable

%endif
