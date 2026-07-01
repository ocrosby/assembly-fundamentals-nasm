; sys_exit(status: rdi) -> noreturn
;
; Wraps the platform's exit syscall. The number differs between
; macOS (BSD class 2, call 1) and Linux (60), which is why every
; program that terminates via syscall has to carry this %ifdef.
; Delegating to a single implementation here keeps that fork in
; one place.

%ifdef MACOS
%define SYS_EXIT 0x2000001          ; BSD class 2, call 1
%else
%define SYS_EXIT 60                 ; Linux exit(2)
%endif

default rel

global sys_exit

section .text

sys_exit:
    mov rax, SYS_EXIT               ; syscall number
    syscall                         ; kernel drops the process
    ret                             ; unreachable; kept so a stray
                                    ; return does not fall through
                                    ; into whatever follows in .text
