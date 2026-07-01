; Use %macro to hide the sys_write and sys_exit boilerplate, then say
; "Hello, world!" and exit with status 42 using just three lines of
; body code in _main.
;
; New in this example: multi-line %macro definitions, invoking a
; macro with positional arguments (%1, %2), and how macros make the
; platform-branching syscall numbers invisible at the call site.

%ifdef MACOS
%define SYS_WRITE 0x2000004
%define SYS_EXIT  0x2000001
%else
%define SYS_WRITE 1
%define SYS_EXIT  60
%endif

default rel
global _start
global _main

section .text

; write_string LABEL, LEN  --  emit a sys_write to stdout.
;   %1 = data label,  %2 = byte count.
%macro write_string 2
    mov rax, SYS_WRITE
    mov rdi, 1                       ; fd = stdout
    lea rsi, [%1]                    ; buffer
    mov rdx, %2                      ; length
    syscall
%endmacro

; exit STATUS  --  emit a sys_exit call.
;   %1 = exit status.
%macro exit 1
    mov rdi, %1
    mov rax, SYS_EXIT
    syscall
%endmacro

_start:
_main:
    write_string hello, hello_len    ; expands to five instructions
    write_string world, world_len    ; expands to five more
    exit 42                          ; expands to three

section .rodata
hello:     db "Hello, "
hello_len: equ $ - hello

world:     db "world!", 10
world_len: equ $ - world
