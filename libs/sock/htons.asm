; htons(x: rdi) -> rax = x with its low 16 bits byte-swapped
;
; Converts a u16 from host byte order (little-endian on x86-64)
; to network byte order (big-endian). The upper 48 bits of rax
; are zeroed. On any little-endian host htons() and ntohs() are
; the same operation.

%include "syscall.inc"

default rel

global htons

section .text

htons:
    movzx eax, di                   ; take low 16 bits, zero-extend
    rol ax, 8                       ; swap the two bytes
    ret
