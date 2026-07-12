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
;   I  memchr: finds 'W' at index 6 of "HELLO WORLD!"
;   J  memchr: miss on n-bounded scan returns NULL
;   K  memchr: n = 0 returns NULL
;   L  strchr: finds 'o' at index 4 of "hello"
;   M  strchr: needle = '\0' returns pointer to the terminator
;   N  strchr: miss returns NULL
;   O  strncmp: equal in first n bytes returns 0 (differ after n)
;   P  strncmp: first differing byte within n returns nonzero
;   Q  strncmp: differing byte at index n is not compared (returns 0)
;   R  strncmp: shorter string is less when the shorter side hits NUL first
;   S  strncmp: n = 0 returns 0
;   T  strcpy: copies "hello" and its terminator into a fresh buffer
;   U  strcpy: returns the original dst pointer

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern memcpy, memset, memcmp, memchr
extern strlen, strcmp, strncmp, strchr, strcpy
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

; v1.1 fixtures.
msg_ab:     db "ab", 0              ; shorter prefix of "abc"
msg_hello3: db "hello", 0           ; distinct copy for strchr misses
msg_abcXX:  db "abcXX", 0           ; strncmp bounded-equality target A
msg_abcYY:  db "abcYY", 0           ; strncmp bounded-equality target B

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
buf_cpy:    resb 8                  ; strcpy destination (v1.1)

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

    ; ---- I: memchr finds 'W' at index 6 of "HELLO WORLD!" ----
    mov byte [fail_id], 'I'
    lea rdi, [ref_hi]
    mov esi, 'W'
    mov rdx, ref_hi_len
    call memchr
    lea rcx, [ref_hi + 6]           ; expected pointer
    cmp rax, rcx
    jne .fail

    ; ---- J: memchr misses within n → NULL ----
    mov byte [fail_id], 'J'
    lea rdi, [ref_hi]
    mov esi, 'Z'                    ; not present in "HELLO WORLD!"
    mov rdx, ref_hi_len
    call memchr
    test rax, rax
    jnz .fail

    ; ---- K: memchr n = 0 → NULL ----
    mov byte [fail_id], 'K'
    lea rdi, [ref_hi]
    mov esi, 'H'                    ; would match index 0 for any n > 0
    xor rdx, rdx
    call memchr
    test rax, rax
    jnz .fail

    ; ---- L: strchr finds 'o' at index 4 of "hello" ----
    mov byte [fail_id], 'L'
    lea rdi, [msg_hello]
    mov esi, 'o'
    call strchr
    lea rcx, [msg_hello + 4]
    cmp rax, rcx
    jne .fail

    ; ---- M: strchr(s, '\0') → pointer to the terminator ----
    mov byte [fail_id], 'M'
    lea rdi, [msg_hello3]
    xor esi, esi                    ; look for '\0'
    call strchr
    lea rcx, [msg_hello3 + 5]       ; "hello" is 5 chars; terminator at 5
    cmp rax, rcx
    jne .fail

    ; ---- N: strchr miss → NULL ----
    mov byte [fail_id], 'N'
    lea rdi, [msg_hello]
    mov esi, 'q'                    ; not present in "hello"
    call strchr
    test rax, rax
    jnz .fail

    ; ---- O: strncmp equal in first n → 0 ----
    mov byte [fail_id], 'O'
    lea rdi, [msg_abcXX]
    lea rsi, [msg_abcYY]
    mov rdx, 3                      ; only compare "abc" vs "abc"
    call strncmp
    test rax, rax
    jnz .fail

    ; ---- P: strncmp first differing byte within n → nonzero ----
    mov byte [fail_id], 'P'
    lea rdi, [msg_abc]              ; "abc"
    lea rsi, [msg_abd]              ; "abd"
    mov rdx, 3
    call strncmp
    ; 'c' (0x63) - 'd' (0x64) = -1 → strictly negative.
    test rax, rax
    jns .fail

    ; ---- Q: strncmp bound stops before the differing byte → 0 ----
    mov byte [fail_id], 'Q'
    lea rdi, [msg_abc]
    lea rsi, [msg_abd]
    mov rdx, 2                      ; only "ab" vs "ab"
    call strncmp
    test rax, rax
    jnz .fail

    ; ---- R: strncmp shorter side < longer when NUL comes first ----
    mov byte [fail_id], 'R'
    lea rdi, [msg_ab]               ; "ab" (NUL at index 2)
    lea rsi, [msg_abc]              ; "abc"
    mov rdx, 5                      ; n larger than either string
    call strncmp
    ; At index 2, msg_ab has '\0' (0) and msg_abc has 'c' (0x63).
    ; 0 - 0x63 = -99 → strictly negative.
    test rax, rax
    jns .fail

    ; ---- S: strncmp n = 0 → 0 regardless of content ----
    mov byte [fail_id], 'S'
    lea rdi, [msg_abc]
    lea rsi, [msg_abZ]
    xor rdx, rdx
    call strncmp
    test rax, rax
    jnz .fail

    ; ---- T: strcpy copies "hello" including the terminator ----
    mov byte [fail_id], 'T'
    ; Pre-fill dst with a distinctive pattern so leftover bytes are
    ; visible if strcpy stops too early. Only the first 6 bytes
    ; (5 chars + NUL) get overwritten; bytes 6..7 stay as sentinels.
    mov byte [buf_cpy + 0], 0xAA
    mov byte [buf_cpy + 1], 0xAA
    mov byte [buf_cpy + 2], 0xAA
    mov byte [buf_cpy + 3], 0xAA
    mov byte [buf_cpy + 4], 0xAA
    mov byte [buf_cpy + 5], 0xAA
    mov byte [buf_cpy + 6], 0xAA
    mov byte [buf_cpy + 7], 0xAA
    lea rdi, [buf_cpy]
    lea rsi, [msg_hello]            ; "hello\0"
    call strcpy
    ; buf_cpy should now hold "hello\0" in bytes 0..5, and the
    ; two sentinels at 6..7 must still be 0xAA.
    lea rdi, [buf_cpy]
    lea rsi, [msg_hello]
    mov rdx, 6                      ; 5 chars + NUL
    call memcmp
    test rax, rax
    jnz .fail
    cmp byte [buf_cpy + 6], 0xAA
    jne .fail
    cmp byte [buf_cpy + 7], 0xAA
    jne .fail

    ; ---- U: strcpy returns the original dst ----
    mov byte [fail_id], 'U'
    lea rdi, [buf_cpy]
    lea rsi, [msg_hello2]
    call strcpy
    lea rcx, [buf_cpy]
    cmp rax, rcx
    jne .fail

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
