; inet6-smoke.asm — smoke test for inet_pton6 and inet_ntop6.
;
; Prints "PASS\n" and exits 0 when every sub-check passes.
; Prints "FAIL:<id>\n" to stderr and exits 1 on the first failure,
; where <id> is a single character identifying the failing check:
;
;   A..I — inet_pton6 successes (::, ::1, 1::, 1::2, full 8-group,
;          2001:db8::1, ::ffff:v4-tail, mixed case, 0:0:...:0)
;   a..n — inet_pton6 rejects (empty, single ':', ':::', double
;          '::' , 9-group, 7-group, 5-hex-digits, invalid hex,
;          v4 octet > 255, short v4 tail, bare v4 no ::,
;          '1:2:3:4:5:6:7:8::' zero-expansion, trailing ':' ,
;          leading ':')
;   1..9 — inet_ntop6 canonical output (all-zero → "::", ::1,
;          1::, 2001:db8::1, full 8-group, IPv4-mapped, RFC 5952
;          first-tie run, single-zero not compressed, all-ffff)
;   z    — buffer-too-small returns NULL
;   R    — pton→ntop→pton round-trip
;
; No syscalls into libsock other than the routines under test —
; write() and exit() go straight to the kernel.

extern inet_pton6, inet_ntop6

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

global _start
global _main

section .data

; ---- pton6 success cases ----
; Each: {ptr, expected 16 bytes network order}
s_dc:       db "::", 0
e_dc:       db 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0

s_dc1:      db "::1", 0
e_dc1:      db 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,1

s_1dc:      db "1::", 0
e_1dc:      db 0,1, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0

s_1dc2:     db "1::2", 0
e_1dc2:     db 0,1, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,2

s_full:     db "1:2:3:4:5:6:7:8", 0
e_full:     db 0,1, 0,2, 0,3, 0,4, 0,5, 0,6, 0,7, 0,8

s_std:      db "2001:db8::1", 0
e_std:      db 0x20,0x01, 0x0d,0xb8, 0,0, 0,0, 0,0, 0,0, 0,0, 0,1

s_v4map:    db "::ffff:192.0.2.1", 0
e_v4map:    db 0,0, 0,0, 0,0, 0,0, 0,0, 0xff,0xff, 192,0, 2,1

s_case:     db "AbCd::1", 0
e_case:     db 0xab,0xcd, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,1

s_all0:     db "0:0:0:0:0:0:0:0", 0
e_all0:     db 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0

; ---- pton6 failure cases ----
f_empty:    db 0
f_single:   db ":", 0
f_triple:   db ":::", 0
f_dq2:      db "::1::2", 0
f_9grp:     db "1:2:3:4:5:6:7:8:9", 0
f_7grp:     db "1:2:3:4:5:6:7", 0
f_5digit:   db "12345::", 0
f_bad:      db "gggg::", 0
f_oct256:   db "::1.2.3.256", 0
f_short_v4: db "::1.2.3", 0
f_bare_v4:  db "1.2.3.4", 0
f_expand0:  db "1:2:3:4:5:6:7:8::", 0
f_trail:    db "1:2:3:4:5:6:7:8:", 0
f_lead:     db ":1:2:3:4:5:6:7:8", 0
f_dqhex:    db "abcd::1.2.3.4", 0     ; hex in a group before dotted quad → OK actually

; ---- ntop6 canonical output expectations ----
; Each: {16-byte src (network order), expected NUL-terminated text}
n_all0_src: db 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0
n_all0_exp: db "::", 0

n_dc1_src:  db 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,1
n_dc1_exp:  db "::1", 0

n_1dc_src:  db 0,1, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0
n_1dc_exp:  db "1::", 0

n_std_src:  db 0x20,0x01, 0x0d,0xb8, 0,0, 0,0, 0,0, 0,0, 0,0, 0,1
n_std_exp:  db "2001:db8::1", 0

n_full_src: db 0,1, 0,2, 0,3, 0,4, 0,5, 0,6, 0,7, 0,8
n_full_exp: db "1:2:3:4:5:6:7:8", 0

n_v4_src:   db 0,0, 0,0, 0,0, 0,0, 0,0, 0xff,0xff, 192,0, 2,1
n_v4_exp:   db "::ffff:192.0.2.1", 0

; First-tie rule: two 2-zero runs — pick the first.
n_tie_src:  db 0,1, 0,0, 0,0, 0,4, 0,5, 0,0, 0,0, 0,8
n_tie_exp:  db "1::4:5:0:0:8", 0

; Single zero should NOT compress.
n_one_src:  db 0,1, 0,2, 0,0, 0,4, 0,5, 0,6, 0,7, 0,8
n_one_exp:  db "1:2:0:4:5:6:7:8", 0

; Max-value groups.
n_max_src:  db 0xff,0xff, 0xff,0xff, 0xff,0xff, 0xff,0xff, 0xff,0xff, 0xff,0xff, 0xff,0xff, 0xff,0xff
n_max_exp:  db "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", 0

pass_msg:   db "PASS", 10
pass_len:   equ $ - pass_msg
fail_hdr:   db "FAIL:"
fail_id:    db "..", 10
fail_len:   equ $ - fail_hdr

section .bss
buf16:      resb 16
outbuf:     resb 64
buf16b:     resb 16

section .text

_start:
_main:
    ; ---- pton6 successes ----
    mov r15b, 'A'
    lea rdi, [s_dc]
    lea rsi, [buf16]
    lea rdx, [e_dc]
    call pton_ok

    mov r15b, 'B'
    lea rdi, [s_dc1]
    lea rsi, [buf16]
    lea rdx, [e_dc1]
    call pton_ok

    mov r15b, 'C'
    lea rdi, [s_1dc]
    lea rsi, [buf16]
    lea rdx, [e_1dc]
    call pton_ok

    mov r15b, 'D'
    lea rdi, [s_1dc2]
    lea rsi, [buf16]
    lea rdx, [e_1dc2]
    call pton_ok

    mov r15b, 'E'
    lea rdi, [s_full]
    lea rsi, [buf16]
    lea rdx, [e_full]
    call pton_ok

    mov r15b, 'F'
    lea rdi, [s_std]
    lea rsi, [buf16]
    lea rdx, [e_std]
    call pton_ok

    mov r15b, 'G'
    lea rdi, [s_v4map]
    lea rsi, [buf16]
    lea rdx, [e_v4map]
    call pton_ok

    mov r15b, 'H'
    lea rdi, [s_case]
    lea rsi, [buf16]
    lea rdx, [e_case]
    call pton_ok

    mov r15b, 'I'
    lea rdi, [s_all0]
    lea rsi, [buf16]
    lea rdx, [e_all0]
    call pton_ok

    ; ---- pton6 failures ----
    mov r15b, 'a'
    lea rdi, [f_empty]
    call pton_fail

    mov r15b, 'b'
    lea rdi, [f_single]
    call pton_fail

    mov r15b, 'c'
    lea rdi, [f_triple]
    call pton_fail

    mov r15b, 'd'
    lea rdi, [f_dq2]
    call pton_fail

    mov r15b, 'e'
    lea rdi, [f_9grp]
    call pton_fail

    mov r15b, 'f'
    lea rdi, [f_7grp]
    call pton_fail

    mov r15b, 'g'
    lea rdi, [f_5digit]
    call pton_fail

    mov r15b, 'h'
    lea rdi, [f_bad]
    call pton_fail

    mov r15b, 'i'
    lea rdi, [f_oct256]
    call pton_fail

    mov r15b, 'j'
    lea rdi, [f_short_v4]
    call pton_fail

    mov r15b, 'k'
    lea rdi, [f_bare_v4]
    call pton_fail

    mov r15b, 'l'
    lea rdi, [f_expand0]
    call pton_fail

    mov r15b, 'm'
    lea rdi, [f_trail]
    call pton_fail

    mov r15b, 'n'
    lea rdi, [f_lead]
    call pton_fail

    ; ---- ntop6 canonical output ----
    mov r15b, '1'
    lea rdi, [n_all0_src]
    lea rsi, [n_all0_exp]
    call ntop_ok

    mov r15b, '2'
    lea rdi, [n_dc1_src]
    lea rsi, [n_dc1_exp]
    call ntop_ok

    mov r15b, '3'
    lea rdi, [n_1dc_src]
    lea rsi, [n_1dc_exp]
    call ntop_ok

    mov r15b, '4'
    lea rdi, [n_std_src]
    lea rsi, [n_std_exp]
    call ntop_ok

    mov r15b, '5'
    lea rdi, [n_full_src]
    lea rsi, [n_full_exp]
    call ntop_ok

    mov r15b, '6'
    lea rdi, [n_v4_src]
    lea rsi, [n_v4_exp]
    call ntop_ok

    mov r15b, '7'
    lea rdi, [n_tie_src]
    lea rsi, [n_tie_exp]
    call ntop_ok

    mov r15b, '8'
    lea rdi, [n_one_src]
    lea rsi, [n_one_exp]
    call ntop_ok

    mov r15b, '9'
    lea rdi, [n_max_src]
    lea rsi, [n_max_exp]
    call ntop_ok

    ; ntop6 buffer-too-small returns NULL
    mov r15b, 'z'
    lea rdi, [n_all0_src]
    lea rsi, [outbuf]
    mov rdx, 45                     ; one short of INET6_ADDRSTRLEN
    call inet_ntop6
    test rax, rax
    jnz .fail

    ; Round-trip: pton(std) → ntop → pton → compare
    mov r15b, 'R'
    lea rdi, [s_std]
    lea rsi, [buf16]
    call inet_pton6
    cmp rax, 1
    jne .fail
    lea rdi, [buf16]
    lea rsi, [outbuf]
    mov rdx, 46
    call inet_ntop6
    test rax, rax
    jz .fail
    lea rdi, [outbuf]
    lea rsi, [buf16b]
    call inet_pton6
    cmp rax, 1
    jne .fail
    ; compare buf16 and buf16b — LEA first so we can use base+index
    ; under `default rel` on Mach-O.
    lea rdi, [buf16]
    lea r14, [buf16b]
    xor ecx, ecx
.rt_loop:
    cmp ecx, 16
    jge .rt_done
    mov al, [rdi + rcx]
    cmp al, [r14 + rcx]
    jne .fail
    inc ecx
    jmp .rt_loop
.rt_done:

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
    mov [fail_id], r15b
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_hdr]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall

; --------------------------------------------------------------
; pton_ok(rdi=src, rsi=dst_buf, rdx=expected_16_bytes)
; Calls inet_pton6, expects rax=1, compares 16 output bytes with
; expected. On mismatch, jumps to the outer .fail label.
; Preserves r15b (the failure id).
pton_ok:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi                    ; save dst buf
    mov r13, rdx                    ; save expected
    call inet_pton6
    cmp rax, 1
    jne .po_fail
    xor ecx, ecx
.po_loop:
    cmp ecx, 16
    jge .po_ok
    mov al, [r12 + rcx]
    cmp al, [r13 + rcx]
    jne .po_fail
    inc ecx
    jmp .po_loop
.po_ok:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.po_fail:
    pop r14
    pop r13
    pop r12
    pop rbx
    jmp _main.fail

; pton_fail(rdi=src)
; Calls inet_pton6 (uses buf16 as dst), expects rax=0.
pton_fail:
    lea rsi, [buf16]
    call inet_pton6
    test rax, rax
    jz .pf_ok
    jmp _main.fail
.pf_ok:
    ret

; ntop_ok(rdi=src_16_bytes, rsi=expected_string)
; Calls inet_ntop6 with 46-byte buffer, expects non-NULL and
; expected string match.
ntop_ok:
    push rbx
    push r12
    mov r12, rsi                    ; expected
    lea rsi, [outbuf]
    mov rdx, 46
    call inet_ntop6
    test rax, rax
    jz .no_fail
    ; strcmp outbuf, r12
    lea rdi, [outbuf]
    mov rsi, r12
.no_loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .no_fail
    test al, al
    jz .no_ok
    inc rdi
    inc rsi
    jmp .no_loop
.no_ok:
    pop r12
    pop rbx
    ret
.no_fail:
    pop r12
    pop rbx
    jmp _main.fail
