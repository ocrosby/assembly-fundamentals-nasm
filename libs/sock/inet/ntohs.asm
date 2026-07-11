; ntohs(x: rdi) -> rax = x with its low 16 bits byte-swapped
;
; Inverse of htons(). On a little-endian x86-64 host both
; directions are byte-identical.

default rel

global ntohs

section .text

ntohs:
    movzx eax, di
    rol ax, 8
    ret
