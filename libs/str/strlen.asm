; strlen(s: rdi) -> length
;
; Walks a NUL-terminated byte string starting at `[s]` and returns
; the number of bytes preceding the terminator. The terminator
; itself is not counted, matching C's `strlen`.
;
; Byte-at-a-time is deliberate — the intent is to read no further
; than the terminator. A word-parallel scan (SWAR or SSE) can read
; past the end of the string when the terminator is not at the
; boundary; that is legal in glibc because malloc always overallocs,
; but this archive makes no such assumption about callers.

default rel

global strlen

section .text

strlen:
    mov rax, rdi                    ; scan cursor; also the return base
.loop:
    cmp byte [rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    sub rax, rdi                    ; length = cursor - start
    ret
