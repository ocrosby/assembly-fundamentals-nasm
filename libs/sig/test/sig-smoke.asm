; sig-smoke.asm — cover every libsig export end to end.
;
; Standalone. Prints "PASS\n" and exits 0 when every sub-check
; passes; calls libasm's `panic` with "FAIL:<id>\n" and exits
; 1 otherwise.
;
; Sub-check ids:
;
;   1  sigprocmask(SIG_SETMASK, {SIGUSR-independent set of
;      SIGPIPE}, oldset) succeeds — 0 return.
;   2  sigprocmask(0, NULL, cur_mask) reads the current mask
;      back — cur_mask now has SIGPIPE's bit set.
;   3  sigprocmask(SIG_UNBLOCK, all_set, NULL) unblocks
;      everything — 0 return.
;   4  sigprocmask(0, NULL, cur_mask) reads the mask; no bits
;      set anymore.
;   5  sigpending(pending) succeeds — 0 return. The set may
;      or may not have bits; the check is only that the
;      wrapper propagates a success return.
;   6  sigprocmask with an obviously bogus how value returns
;      negative errno — proves error normalization on the
;      macOS SYSCALL_NORM path fires end to end.
;   7  sig_zero(buf) on a pre-dirtied buffer clears every
;      SIGSET_BYTES byte to 0.
;   8  sig_add(buf, SIGPIPE) sets exactly bit 12 (SIGPIPE - 1).
;   9  sig_test(buf, SIGPIPE) returns 1.
;   A  sig_test(buf, SIGINT) returns 0 (never added).
;   B  sig_del(buf, SIGPIPE) clears bit 12.
;   C  sig_test(buf, SIGPIPE) returns 0 after sig_del.
;   D  sig_zero + sig_add + sigprocmask round-trip: build a
;      SIGPIPE-only mask via the helpers, install it, read
;      it back, confirm the SIGPIPE bit landed — proves the
;      helpers produce the same wire format the kernel expects.
;   E  sigaction(SIGPIPE, {sa_handler = SIG_IGN}, NULL) → 0.
;      Installs SIG_IGN via the v1.2 wrapper.
;   F  Write to a pipe with its read end closed. Now that
;      SIGPIPE is ignored (v1.2 SIG_IGN), the syscall returns
;      -EPIPE without terminating the process — the same
;      "we survive" outcome 38-signal-block reached via
;      sigprocmask, but reached via disposition instead.
;   G  sigaction(SIGPIPE, NULL, &old) reads the disposition
;      back — old.sa_handler must equal SIG_IGN.
;   H  sigaction(SIGPIPE, {sa_handler = SIG_DFL}, NULL) → 0.
;      Restores the default disposition (which for SIGPIPE
;      would terminate the process; we never fire it again).

%include "syscall.inc"

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_read  0x2000003
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_read  0
%define SYS_close 3
%define SYS_exit  60
%endif

default rel

extern sigprocmask, sigpending, sigaction
extern sig_zero, sig_add, sig_del, sig_test
extern pipe                         ; libio v1.7
extern panic                        ; libasm

global _start
global _main

section .rodata
pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
; Each sigset buffer is 8 bytes even on macOS (where the kernel
; only reads 4). The upper 4 bytes stay 0 and the extra space
; is free.
set_pipe: resq 1                    ; will hold bit for SIGPIPE
all_set:  resq 1                    ; 0xFFFFFFFFFFFFFFFF
cur_mask: resq 1                    ; oldset out slot
pending:  resq 1
util_buf: resq 1                    ; scratch for v1.1 util helpers
util_msk: resq 1                    ; oldset out for sub-check D

; v1.2 sigaction fixtures. .bss defaults to zero, so
; sa_handler / sa_mask / sa_flags all start at 0. The smoke
; only overwrites sa_handler.
act:      resb SIGACTION_SIZE       ; new action buffer
oldact:   resb SIGACTION_SIZE       ; oldact readback buffer
pipefd:   resd 2                    ; libio pipe writes 2 fds here
sig_buf:  resb 4                    ; scratch for the pipe write

section .text

_start:
_main:
    ; ---- Prep: build a set with only SIGPIPE (bit 12) set ----
    ; POSIX bit index for signal N is (N - 1). SIGPIPE = 13, so
    ; bit 12 = 1 << 12 = 0x1000.
    mov qword [set_pipe], 1 << (SIGPIPE - 1)
    mov qword [all_set], -1         ; every bit
    mov qword [cur_mask], 0         ; canary; sigprocmask will overwrite
    mov qword [pending], 0

    ; ---- 1: sigprocmask(SIG_SETMASK, set_pipe, cur_mask) → 0 ----
    mov byte [fail_id], '1'
    mov edi, SIG_SETMASK
    lea rsi, [set_pipe]
    lea rdx, [cur_mask]
    call sigprocmask
    test rax, rax
    jnz .fail

    ; ---- 2: read the mask back — SIGPIPE bit should be set ----
    ; sigprocmask(0, NULL, cur_mask) is the "just tell me the
    ; current mask" form on both platforms; how is ignored.
    mov byte [fail_id], '2'
    xor edi, edi
    xor esi, esi                    ; set = NULL
    lea rdx, [cur_mask]
    call sigprocmask
    test rax, rax
    jnz .fail
    ; The mask must have the SIGPIPE bit set (bit 12). Test
    ; that bit specifically; other bits may be nonzero on
    ; platforms that inherit implicit masks from init.
    mov rax, [cur_mask]
    test rax, 1 << (SIGPIPE - 1)
    jz .fail

    ; ---- 3: sigprocmask(SIG_UNBLOCK, all_set, NULL) → 0 ----
    mov byte [fail_id], '3'
    mov edi, SIG_UNBLOCK
    lea rsi, [all_set]
    xor edx, edx                    ; oldset = NULL
    call sigprocmask
    test rax, rax
    jnz .fail

    ; ---- 4: read the mask back — SIGPIPE bit should be clear ----
    mov byte [fail_id], '4'
    xor edi, edi
    xor esi, esi
    lea rdx, [cur_mask]
    call sigprocmask
    test rax, rax
    jnz .fail
    mov rax, [cur_mask]
    test rax, 1 << (SIGPIPE - 1)
    jnz .fail                       ; must be clear now

    ; ---- 5: sigpending(pending) → 0 ----
    mov byte [fail_id], '5'
    lea rdi, [pending]
    call sigpending
    test rax, rax
    jnz .fail

    ; ---- 6: sigprocmask with bad `how` → negative errno ----
    ; A `how` value of 999 is out of range on both platforms.
    mov byte [fail_id], '6'
    mov edi, 999
    lea rsi, [set_pipe]
    xor edx, edx
    call sigprocmask
    test rax, rax
    jns .fail                       ; want strictly negative

    ; ---- 7: sig_zero on a dirty buffer clears every byte ----
    ; Prime util_buf with a distinctive pattern so leftover
    ; bytes fail the check. Only the SIGSET_BYTES-sized head
    ; is primed and inspected — that is the region sig_zero
    ; is contracted to clear (4 bytes on macOS, 8 on Linux;
    ; see syscall.inc).
    mov byte [fail_id], '7'
%ifdef MACOS
    mov dword [util_buf], -1
%else
    mov qword [util_buf], -1
%endif
    lea rdi, [util_buf]
    call sig_zero
%ifdef MACOS
    cmp dword [util_buf], 0
%else
    cmp qword [util_buf], 0
%endif
    jne .fail

    ; ---- 8: sig_add(buf, SIGPIPE) sets exactly bit 12 ----
    ; util_buf was zeroed in sub-check 7. After adding SIGPIPE
    ; the sigset should read 1 << 12 = 0x1000 in the low
    ; SIGSET_BYTES bytes.
    mov byte [fail_id], '8'
    lea rdi, [util_buf]
    mov esi, SIGPIPE
    call sig_add
%ifdef MACOS
    mov eax, [util_buf]
    cmp eax, 1 << (SIGPIPE - 1)
%else
    mov rax, [util_buf]
    cmp rax, 1 << (SIGPIPE - 1)
%endif
    jne .fail

    ; ---- 9: sig_test(buf, SIGPIPE) → 1 ----
    mov byte [fail_id], '9'
    lea rdi, [util_buf]
    mov esi, SIGPIPE
    call sig_test
    cmp rax, 1
    jne .fail

    ; ---- A: sig_test(buf, SIGINT) → 0 (never added) ----
    mov byte [fail_id], 'A'
    lea rdi, [util_buf]
    mov esi, SIGINT
    call sig_test
    test rax, rax
    jnz .fail

    ; ---- B: sig_del(buf, SIGPIPE) clears bit 12 ----
    mov byte [fail_id], 'B'
    lea rdi, [util_buf]
    mov esi, SIGPIPE
    call sig_del
%ifdef MACOS
    cmp dword [util_buf], 0
%else
    cmp qword [util_buf], 0
%endif
    jne .fail

    ; ---- C: sig_test(buf, SIGPIPE) → 0 after sig_del ----
    mov byte [fail_id], 'C'
    lea rdi, [util_buf]
    mov esi, SIGPIPE
    call sig_test
    test rax, rax
    jnz .fail

    ; ---- D: helper-built mask survives the sigprocmask ----
    ; round-trip: zero, add SIGPIPE, install via SIG_SETMASK,
    ; read back, confirm SIGPIPE lands. Proves the helpers
    ; emit the same wire format the kernel expects.
    mov byte [fail_id], 'D'
    lea rdi, [util_buf]
    call sig_zero
    lea rdi, [util_buf]
    mov esi, SIGPIPE
    call sig_add
    mov edi, SIG_SETMASK
    lea rsi, [util_buf]
    lea rdx, [util_msk]              ; oldset — we do not check it
    call sigprocmask
    test rax, rax
    jnz .fail
    xor edi, edi
    xor esi, esi
    lea rdx, [cur_mask]
    call sigprocmask
    test rax, rax
    jnz .fail
    mov rax, [cur_mask]
    test rax, 1 << (SIGPIPE - 1)
    jz .fail

    ; ---- E: sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL) → 0 ----
    ; Build the struct in .bss which is zero-initialized —
    ; only sa_handler needs to be set. The other fields
    ; (sa_mask, sa_flags, sa_tramp on macOS, sa_restorer on
    ; Linux) stay 0, which is safe for SIG_IGN since the
    ; kernel never invokes a userspace trampoline when the
    ; disposition is "ignore".
    mov byte [fail_id], 'E'
    mov qword [act + SA_HANDLER_OFF], SIG_IGN
    mov edi, SIGPIPE
    lea rsi, [act]
    xor edx, edx                    ; oldact = NULL
    call sigaction
    test rax, rax
    jnz .fail

    ; ---- F: write to a broken pipe returns -EPIPE ----
    ; With SIGPIPE ignored, the signal is discarded and
    ; write returns -EPIPE instead of terminating the
    ; process. First unblock everything so the SIG_IGN
    ; disposition (not the sigprocmask block) is what
    ; survives the write. The v1.2 wrapper's success on
    ; sub-check E is worth nothing without this end-to-end
    ; observation.
    mov byte [fail_id], 'F'
    mov edi, SIG_UNBLOCK
    lea rsi, [all_set]
    xor edx, edx
    call sigprocmask
    test rax, rax
    jnz .fail

    ; pipe(pipefd)
    lea rdi, [pipefd]
    call pipe
    test rax, rax
    jnz .fail

    ; close(pipefd[0]) via raw syscall — libio does not
    ; export close and pulling libsock in for one call would
    ; churn the smoke's dep graph.
    mov edi, [pipefd]
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_ok
    neg rax
.close_ok:
%endif
    test rax, rax
    jnz .fail

    ; write(pipefd[1], sig_buf, 1) — raw syscall for the
    ; same reason. Expected return: -EPIPE (negative).
    mov edi, [pipefd + 4]
    lea rsi, [sig_buf]
    mov edx, 1
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .write_ok
    neg rax
.write_ok:
%endif
    test rax, rax
    jns .fail                       ; want strictly negative

    ; ---- G: read the disposition back ----
    ; sigaction(SIGPIPE, NULL, &old) leaves the disposition
    ; alone and writes the current one into `old`.
    ; old.sa_handler must equal SIG_IGN.
    mov byte [fail_id], 'G'
    mov edi, SIGPIPE
    xor esi, esi                    ; act = NULL
    lea rdx, [oldact]
    call sigaction
    test rax, rax
    jnz .fail
    cmp qword [oldact + SA_HANDLER_OFF], SIG_IGN
    jne .fail

    ; ---- H: restore SIG_DFL for hygiene ----
    ; Reset act.sa_handler and install. We never fire
    ; SIGPIPE again in this process, so the default
    ; disposition (terminate) is safe.
    mov byte [fail_id], 'H'
    mov qword [act + SA_HANDLER_OFF], SIG_DFL
    mov edi, SIGPIPE
    lea rsi, [act]
    xor edx, edx
    call sigaction
    test rax, rax
    jnz .fail

    ; Close the write end of the pipe so the smoke does not
    ; leak an fd.
    mov edi, [pipefd + 4]
    mov rax, SYS_close
    syscall

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
