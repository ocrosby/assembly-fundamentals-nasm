; ntohl(x: rdi) -> rax = x with its low 32 bits byte-reversed
;
; Inverse of htonl(); byte-identical on a little-endian host.

default rel

global ntohl

section .text

ntohl:
    mov eax, edi
    bswap eax
    ret
