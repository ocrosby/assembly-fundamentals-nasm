; syscall-common.inc — macros every syscall wrapper needs.
;
; This file lives one directory up from each library's own
; syscall.inc so all four archives that make direct kernel
; syscalls (libsock, libio, libproc, libresolv) can `%include
; "../syscall-common.inc"` at the top of their private
; syscall.inc without either coupling their build to the
; others or shipping a hand-copied duplicate of these seven
; instruction lines.
;
; The %ifndef guard lets libraries include each other's
; syscall.inc files (libresolv's wrappers pull in libsock's
; syscall.inc for AF_INET / SIN_HEADER / etc.) without a
; redefinition error.

%ifndef LIBS_SYSCALL_COMMON_INC
%define LIBS_SYSCALL_COMMON_INC

; SYSCALL_NORM — normalizes the macOS carry-flag error
; convention to Linux's "negative errno in rax" convention,
; so every wrapper returns non-negative on success and a
; negative errno on failure regardless of platform. On
; Linux the macro is just `syscall` because the kernel
; already writes -errno into rax.
%macro SYSCALL_NORM 0
    syscall
%ifdef MACOS
    jnc %%ok                        ; CF=0 → success
    neg rax                         ; CF=1 → positive errno → -errno
%%ok:
%endif
%endmacro

; SYSCALL_ARG4 — the System V AMD64 ABI passes the 4th
; argument in rcx, but the kernel's syscall ABI clobbers rcx
; (it holds the return address) and expects the 4th arg in
; r10. Wrappers with four or more arguments must translate
; rcx → r10 before invoking the syscall.
%macro SYSCALL_ARG4 0
    mov r10, rcx                    ; 4th arg: SysV rcx → syscall r10
%endmacro

%endif ; LIBS_SYSCALL_COMMON_INC
