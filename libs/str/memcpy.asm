; memcpy(dst: rdi, src: rsi, n: rdx) -> dst
;
; Copies `n` bytes from `[src]` to `[dst]` and returns the
; original `dst` pointer. Byte-granularity via `rep movsb`; the
; kernel micro-op fusion on modern x86-64 makes this competitive
; with hand-rolled 8-byte loops on the small buffers this library
; targets. Callers who need a memcpy that saturates DRAM bandwidth
; are outside the scope of the study repo — reach for glibc or
; SIMD there.
;
; Semantics match C's `memcpy`: the buffers **must not overlap**.
; Overlap is undefined behavior here; for overlap-safe copies use
; a hypothetical `memmove` (not shipped in this archive).
;
; `n = 0` is legal and returns `dst` unchanged.

default rel

global memcpy

section .text

memcpy:
    mov rax, rdi                    ; preserve dst for return
    mov rcx, rdx                    ; rep movsb wants the count in rcx
    ; rdi already = dst, rsi already = src.
    rep movsb                       ; copy rcx bytes [rsi] -> [rdi]
    ret
