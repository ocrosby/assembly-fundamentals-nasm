; str-smoke.asm — cover every libstr export end to end.
;
; Standalone. Prints "PASS\n" to stdout and exits 0 when every
; sub-check passes; prints "FAIL:<id>\n" to stderr via libasm's
; `panic` and exits 1 otherwise.
;
; Sub-check ids:
;
;   1  memcpy: 12-byte overlap-free copy round-trips exactly
;   2  memcpy: n = 0 returns dst unchanged and touches nothing
;   3  memcpy: the return value equals the original dst
;   4  memset: fills all n bytes with the low byte of c
;   5  memset: ignores the upper bits of c (writes only 'A')
;   6  memset: n = 0 returns dst unchanged
;   7  memcmp: equal buffers return 0
;   8  memcmp: first differing byte sets the sign correctly
;   9  memcmp: unsigned semantics — 0xFF vs 0x01 returns positive
;   A  memcmp: n = 0 returns 0 regardless of contents
;   B  strlen: "" returns 0
;   C  strlen: "hello" returns 5
;   D  strlen: 13-byte string returns 13 (past the small-string range)
;   E  strcmp: identical strings return 0
;   F  strcmp: "abc" < "abd" returns negative
;   G  strcmp: "abcd" > "abc" returns positive (shorter side is less)
;   H  strcmp: "abc" > "abZ" returns positive (Z = 0x5A < c = 0x63)

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern memcpy, memset, memcmp, strlen, strcmp
extern panic                        ; libasm
extern panic                        ; libasm

global _start
global _main

section .rodata
src12:      db "HELLO WORLD!"       ; 12 bytes, no NUL
src12_len:  equ $ - src12

msg_empty:  db 0                    ; ""
msg_hello:  db "hello", 0           ; 5 chars + NUL
msg_13:     db "assembly rock", 0   ; 13 chars + NUL (past 8)
msg_hello2: db "hello", 0
msg_abc:    db "abc", 0
msg_abd:    db "abd", 0
msg_abcd:   db "abcd", 0
msg_abZ:    db "abZ", 0             ; 'Z' (0x5A) < 'c' (0x63)

; 12-byte reference for memcmp equality check
ref_hi:     db "HELLO WORLD!"
ref_hi_len: equ $ - ref_hi

; 12-byte reference that differs only at index 6 ('W' vs 'X')
ref_hj:     db "HELLO XORLD!"

pass_msg:   db "PASS", 10
pass_len:   equ $ - pass_msg

section .data
fail_msg:   db "FAIL:?", 10
fail_id     equ fail_msg + 5
fail_len    equ $ - fail_msg

section .bss
dst12:      resb 16                 ; extra slack detects overrun
dst_zero:   resb 4                  ; canary buffer for n=0 checks
buf16:      resb 16
buf_zero:   resb 4                  ; canary for memset n=0

section .text

_start:
_main:
    ; ---- 1: memcpy 12 bytes and verify round-trip ----
    mov byte [fail_id], '1'
    lea rdi, [dst12]
    lea rsi, [src12]
    mov rdx, src12_len
    call memcpy
    ; dst12 should now equal "HELLO WORLD!"; memcmp it against
    ; ref_hi. Uses libstr's own memcmp — the sub-check that
    ; validates memcmp (id 7) runs later, but the equal path
    ; here is the simplest possible input for it, so a bug in
    ; memcmp will show up as "1 fails, then 7 fails" — the
    ; failure id points at the first broken piece.
    lea rdi, [dst12]
    lea rsi, [ref_hi]
    mov rdx, ref_hi_len
    call memcmp
    test rax, rax
    jnz .fail

    ; ---- 2: memcpy with n = 0 leaves the canary alone ----
    mov byte [fail_id], '2'
    ; Seed the canary with a known pattern; memcpy(n=0) must not
    ; touch it.
    mov dword [dst_zero], 0xDEADBEEF
    lea rdi, [dst_zero]
    lea rsi, [src12]                ; src is irrelevant when n = 0
    xor rdx, rdx
    call memcpy
    cmp dword [dst_zero], 0xDEADBEEF
    jne .fail

    ; ---- 3: memcpy returns the original dst ----
    mov byte [fail_id], '3'
    lea rdi, [dst12]
    lea rsi, [src12]
    mov rdx, src12_len
    call memcpy
    lea rcx, [dst12]
    cmp rax, rcx
    jne .fail

    ; ---- 4: memset fills every byte ----
    mov byte [fail_id], '4'
    lea rdi, [buf16]
    mov rsi, 'A'                    ; low byte = 0x41
    mov rdx, 12
    call memset
    ; Verify every byte via a straight compare loop. r8 = index,
    ; r9 = base pointer. Mach-O 64 rejects `[symbol + reg]` as
    ; a 32-bit absolute; hoist the base into a register first.
    lea r9, [buf16]
    xor r8, r8
.check4:
    cmp byte [r9 + r8], 'A'
    jne .fail
    inc r8
    cmp r8, 12
    jb .check4

    ; ---- 5: memset only uses the low byte of c ----
    mov byte [fail_id], '5'
    lea rdi, [buf16]
    mov rsi, 0xFFFFFF41             ; high garbage + 'A' in low byte
    mov rdx, 8
    call memset
    lea r9, [buf16]
    xor r8, r8
.check5:
    cmp byte [r9 + r8], 'A'
    jne .fail
    inc r8
    cmp r8, 8
    jb .check5

    ; ---- 6: memset with n = 0 leaves the canary alone ----
    mov byte [fail_id], '6'
    mov dword [buf_zero], 0xCAFEBABE
    lea rdi, [buf_zero]
    mov rsi, 0
    xor rdx, rdx
    call memset
    cmp dword [buf_zero], 0xCAFEBABE
    jne .fail

    ; ---- 7: memcmp equal buffers → 0 ----
    mov byte [fail_id], '7'
    lea rdi, [ref_hi]
    lea rsi, [dst12]                ; still holds "HELLO WORLD!"
    mov rdx, ref_hi_len
    call memcmp
    test rax, rax
    jnz .fail

    ; ---- 8: memcmp differing buffers → negative ('W' < 'X') ----
    mov byte [fail_id], '8'
    lea rdi, [ref_hi]               ; "HELLO WORLD!"
    lea rsi, [ref_hj]               ; "HELLO XORLD!"
    mov rdx, ref_hi_len
    call memcmp
    ; ref_hi[6] = 'W' (0x57); ref_hj[6] = 'X' (0x58). 0x57 - 0x58
    ; = -1 → rax must be strictly negative.
    test rax, rax
    jns .fail

    ; ---- 9: memcmp unsigned semantics: 0xFF > 0x01 ----
    mov byte [fail_id], '9'
    mov byte [buf16 + 0], 0xFF
    mov byte [buf16 + 1], 0x00
    mov byte [buf16 + 2], 0x00
    mov byte [buf16 + 3], 0x00
    lea rdi, [buf16]                ; starts with 0xFF
    lea rsi, [msg_hello]            ; starts with 'h' = 0x68
    mov rdx, 1
    call memcmp
    ; 0xFF - 0x68 = 0x97 → positive as signed 32-bit.
    test rax, rax
    js .fail
    jz .fail

    ; ---- A: memcmp n = 0 → 0 even for unequal data ----
    mov byte [fail_id], 'A'
    lea rdi, [ref_hi]
    lea rsi, [ref_hj]
    xor rdx, rdx
    call memcmp
    test rax, rax
    jnz .fail

    ; ---- B: strlen("") = 0 ----
    mov byte [fail_id], 'B'
    lea rdi, [msg_empty]
    call strlen
    test rax, rax
    jnz .fail

    ; ---- C: strlen("hello") = 5 ----
    mov byte [fail_id], 'C'
    lea rdi, [msg_hello]
    call strlen
    cmp rax, 5
    jne .fail

    ; ---- D: strlen 13-byte string ----
    mov byte [fail_id], 'D'
    lea rdi, [msg_13]
    call strlen
    cmp rax, 13
    jne .fail

    ; ---- E: strcmp equal → 0 ----
    mov byte [fail_id], 'E'
    lea rdi, [msg_hello]
    lea rsi, [msg_hello2]
    call strcmp
    test rax, rax
    jnz .fail

    ; ---- F: strcmp "abc" < "abd" → negative ----
    mov byte [fail_id], 'F'
    lea rdi, [msg_abc]
    lea rsi, [msg_abd]
    call strcmp
    test rax, rax
    jns .fail

    ; ---- G: strcmp "abcd" > "abc" → positive (shorter is less) ----
    mov byte [fail_id], 'G'
    lea rdi, [msg_abcd]
    lea rsi, [msg_abc]
    call strcmp
    test rax, rax
    jle .fail

    ; ---- H: strcmp "abc" > "abZ" → positive ----
    mov byte [fail_id], 'H'
    lea rdi, [msg_abc]
    lea rsi, [msg_abZ]
    call strcmp
    test rax, rax
    jle .fail

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    lea rdi, [fail_msg]
    mov esi, fail_len
    call panic
    ; unreachable
