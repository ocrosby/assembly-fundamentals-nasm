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
; SYSCALL_NORM and SYSCALL_ARG4 come from
; `syscall-common.inc` — every syscall-making archive
; under `libs/` shares that file so the macros only have to
; change in one place.

%ifndef LIBRESOLV_SYSCALL_INC
%define LIBRESOLV_SYSCALL_INC

%include "syscall-common.inc"

%ifdef MACOS
%define SYS_getentropy 0x20001f4
%else
%define SYS_getrandom  318
%endif

%endif ; LIBRESOLV_SYSCALL_INC
