; panic(msg: rdi, len: rsi) -> noreturn
;
; Write `msg` (len bytes) to stderr, then terminate the process
; with exit code 1. Convenience helper for smoke tests and
; example `.fail` paths — every one of them was hand-rolling
; the same eight lines:
;
;     mov rax, SYS_write
;     mov edi, 2
;     lea rsi, [fail_msg]
;     mov edx, fail_len
;     syscall
;     mov rax, SYS_exit
;     mov edi, 1
;     syscall
;
; With `panic` linked in, the same block becomes three lines:
;
;     lea rdi, [fail_msg]
;     mov esi, fail_len
;     call panic
;
; Arguments:
;   rdi = msg*   pointer to the message bytes. `msg` is not
;                required to be NUL-terminated — `len` gives
;                the exact number of bytes to write.
;   rsi = len    bytes to write.
;
; Does not return. On the write failing (a rare but possible
; case if stderr has been closed), the process still exits
; with status 1 — the caller's intent was "fail loudly" and
; the intent is honored even if the loud part fails.

%ifdef MACOS
%define SYS_WRITE 0x2000004         ; BSD class 2, call 4
%define SYS_EXIT  0x2000001         ; BSD class 2, call 1
%else
%define SYS_WRITE 1                 ; Linux write(2)
%define SYS_EXIT  60                ; Linux exit(2)
%endif

default rel

global panic

section .text

panic:
    ; write(2, msg, len). SysV puts msg in rdi and len in rsi;
    ; write's syscall ABI wants fd/buf/len in rdi/rsi/rdx.
    ; Move len (rsi → rdx) before overwriting rsi with the
    ; buf pointer (rdi → rsi), then set rdi = 2 (stderr).
    mov rdx, rsi                    ; len
    mov rsi, rdi                    ; buf
    mov edi, 2                      ; stderr
    mov rax, SYS_WRITE
    syscall
    ; Ignore whatever write returned — even if it errored,
    ; the exit is what matters.
    mov rax, SYS_EXIT
    mov edi, 1
    syscall
    ; Unreachable; leave a ret so a stray return does not
    ; fall through into whatever follows in .text.
    ret
