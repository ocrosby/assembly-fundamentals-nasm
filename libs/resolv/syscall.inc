; syscall.inc — shared per-platform syscall numbers and macros
;
; Every wrapper in libresolv that touches a syscall includes this
; file. The DNS-transport pieces (socket, sendto, recvfrom, close,
; setsockopt) live in libsock; libresolv only needs its own
; syscall wrapper for random-ID generation, so only that one
; SYS_* number is defined here. If the surface grows —
; poll for finer-grained timeout, for example — additional
; SYS_* defines land alongside.
;
; The SYSCALL_NORM / SYSCALL_ARG4 macros are duplicated across
; libsock, libio, and libresolv so each archive stays self-
; contained. If a fourth archive lands with the same pattern
; the shared macros should promote to a libs/-level include.

%ifndef LIBRESOLV_SYSCALL_INC
%define LIBRESOLV_SYSCALL_INC

%ifdef MACOS
%define SYS_getentropy 0x20001f4
%else
%define SYS_getrandom  318
%endif

%macro SYSCALL_NORM 0
    syscall
%ifdef MACOS
    jnc %%ok                        ; CF=0 → success
    neg rax                         ; CF=1 → positive errno → -errno
%%ok:
%endif
%endmacro

%macro SYSCALL_ARG4 0
    mov r10, rcx                    ; 4th arg: SysV rcx → syscall r10
%endmacro

%endif ; LIBRESOLV_SYSCALL_INC
