; Sum a 5-element int64 array and return the sum as the exit status.
; Expected: 10 + 20 + 30 + 40 + 50 = 150. See docs/13-loops.md.

%ifdef MACOS
%define SYS_EXIT 0x2000001
%else
%define SYS_EXIT 60
%endif

            default rel
            global  _start
            global  _main

            section .text
_start:
_main:      xor     rax, rax                ; accumulator
            xor     rcx, rcx                ; index
            lea     rbx, [arr]              ; rbx = &arr (RIP-relative)
.next:      cmp     rcx, arr_len
            jge     .done
            add     rax, [rbx + rcx*8]      ; load arr[rcx]
            inc     rcx
            jmp     .next

.done:      mov     rdi, rax                ; exit status = sum
            mov     rax, SYS_EXIT
            syscall

            section .data
arr:        dq      10, 20, 30, 40, 50
arr_len:    equ     ($ - arr) / 8
