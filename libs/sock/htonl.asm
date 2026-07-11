; htonl(x: rdi) -> rax = x with its low 32 bits byte-reversed
;
; Converts a u32 from host to network byte order. The upper 32
; bits of rax are zeroed by the mov into eax.

%include "syscall.inc"

default rel

global htonl

section .text

htonl:
    mov eax, edi                    ; low 32 bits, zero-extend
    bswap eax                       ; reverse the 4 bytes
    ret
