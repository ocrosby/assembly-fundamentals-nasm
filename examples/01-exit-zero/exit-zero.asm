; The smallest program that does anything observable: ask the OS to
; terminate this process with status 0.
;
; New in this example: sections, entry symbols, syscall mechanics.

%ifdef MACOS
%define SYS_EXIT 0x2000001          ; macOS BSD syscall class 2, call 1
%else
%define SYS_EXIT 60                 ; Linux x86-64 sys_exit
%endif

default rel                         ; default to RIP-relative addressing
global _start                       ; Linux entry symbol
global _main                        ; macOS entry symbol

section .text

_start:                             ; Linux jumps here
_main:                              ; macOS jumps here (same address)
    mov rax, SYS_EXIT               ; syscall number goes in rax
    xor rdi, rdi                    ; arg 1 = 0  (xor self is shorter than mov 0)
    syscall                         ; sys_exit(0) — kernel never returns
