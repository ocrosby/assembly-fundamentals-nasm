; Sum a 5-element int64 array and return the sum as the exit status.
; Expected: 10 + 20 + 30 + 40 + 50 = 150.
;
; New in this example: the `.data` section, indexed addressing, and
; the load-base-pointer-then-index pattern. Mach-O 64-bit forbids
; `[arr + rcx*8]` with an absolute displacement, so going through a
; base register in `rbx` keeps this source portable.

%ifdef MACOS
%define SYS_EXIT 0x2000001
%else
%define SYS_EXIT 60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    xor rax, rax                    ; rax = running sum (accumulator)
    xor rcx, rcx                    ; rcx = loop index
    lea rbx, [arr]                  ; rbx = &arr (RIP-relative load of the base address)
.next:
    cmp rcx, arr_len                ; have we walked the whole array?
    jge .done                       ; yes — exit the loop
    add rax, [rbx + rcx*8]          ; sum += arr[rcx]   (scale 8 = sizeof(int64))
    inc rcx                         ; rcx += 1
    jmp .next

.done:
    mov rdi, rax                    ; arg 1: exit status = sum
    mov rax, SYS_EXIT
    syscall                         ; sys_exit(sum)

section .data
arr: dq 10, 20, 30, 40, 50          ; five 8-byte integers
arr_len: equ ($ - arr) / 8          ; element count, computed at assemble time
