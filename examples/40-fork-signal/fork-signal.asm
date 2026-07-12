; Fork a child that would sleep for 10 seconds, send it
; SIGTERM from the parent, then wait4 and confirm the child
; was terminated by a signal (not a normal exit). Exit 42 on
; success; exit 1 on any anomaly.
;
; First runnable that uses libproc's `kill`. Demonstrates the
; process-control triangle libproc was built for:
;
;   fork()                      → duplicate this process
;   kill(child_pid, SIGTERM)    → send a signal to the copy
;   wait4(child_pid, &status)   → reap the corpse and read
;                                 how it died
;
; wait4 fills a status word whose layout is the same on macOS
; and Linux (POSIX standardized it):
;
;   status & 0x7f == 0                → normal exit; exit code
;                                       is (status >> 8) & 0xff
;   status & 0x7f == 0x7f             → child is stopped, not
;                                       reaped (WUNTRACED)
;   (status & 0x7f) != 0 && != 0x7f   → terminated by signal;
;                                       signal number is
;                                       status & 0x7f
;
; This example fires only in the third case: the child was
; killed by our SIGTERM. Signal number 15 (SIGTERM) appears
; in the low 7 bits.

%include "syscall.inc"                  ; libsig's — for SIGTERM

%ifdef MACOS
%define SYS_exit    0x2000001
%else
%define SYS_exit    60
%endif

default rel

extern fork, kill, wait4                ; libproc
extern sleep_ms                         ; libtime

global _start
global _main

section .bss
status:  resq 1                         ; wait4 stores the packed status here

section .text

_start:
_main:
    ; ---- fork() ----
    call fork
    test rax, rax
    js .fail                            ; -errno
    jz .child                           ; child sees rax = 0

    ; ================================================================
    ; Parent — send SIGTERM, reap the child, verify signal death.
    ; ================================================================
    mov r12d, eax                       ; save child pid (callee-saved)

    ; kill(child, SIGTERM). If the child has not yet been
    ; scheduled, the kernel queues the signal in its pending
    ; set — sending immediately after fork is safe.
    mov edi, r12d
    mov esi, SIGTERM
    call kill
    test rax, rax
    jnz .fail                           ; child gone, permission denied, ...

    ; wait4(child, &status, 0, NULL). options = 0 blocks until
    ; the child terminates; rusage = NULL because we do not
    ; care about accounting stats here.
    mov edi, r12d
    lea rsi, [status]
    xor edx, edx                        ; options
    xor ecx, ecx                        ; rusage*
    call wait4
    ; wait4 returns the reaped pid on success. Anything else
    ; (0 with WNOHANG, or a negative errno) is a failure here
    ; since we blocked.
    cmp eax, r12d
    jne .fail

    ; Verify the low 7 bits of status equal SIGTERM. If the
    ; child got scheduled long enough to complete sleep_ms and
    ; call sys_exit(0), status & 0x7f would be 0 and this
    ; check would fail — but sleep_ms(10000) is a 10-second
    ; wait, so realistically we always kill before it
    ; returns.
    mov eax, [status]
    and eax, 0x7f
    cmp eax, SIGTERM
    jne .fail

    ; exit(42)
    mov rax, SYS_exit
    mov edi, 42
    syscall

    ; ================================================================
    ; Child — sleep long enough that the parent's kill lands
    ; before we could naturally exit.
    ; ================================================================
.child:
    mov edi, 10000                      ; 10 seconds
    call sleep_ms
    ; If sleep_ms returns normally, no signal arrived — bail
    ; out with a distinctive status the parent can detect via
    ; (status >> 8) & 0xff.
    mov rax, SYS_exit
    mov edi, 99                         ; "child was not killed" sentinel
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
