; sig_tramp — placeholder for the macOS sa_tramp trampoline
;
; v1.3 ships custom handler support on **Linux only** via
; `sig_restorer` (see util/sig-restorer.asm). macOS's
; equivalent requires an sa_tramp stub that invokes
; SYS_sigreturn(uctx, sigstyle, token) — and the token
; argument is validated against a value the kernel stores in
; the signal frame at delivery. Locating that token in the
; frame layout requires reading Darwin xnu internals in a way
; that has not been done for this archive yet.
;
; Until it is, macOS callers keep v1.2's SIG_DFL / SIG_IGN
; support; installing a custom handler on macOS from this
; archive is not supported.
;
; This file conditionally compiles nothing on both platforms
; so the archive builds cleanly on macOS without exposing a
; broken `sig_tramp` symbol.

%include "syscall.inc"

; Intentionally empty on both platforms.
