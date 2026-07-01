; Call `divmod(17, 5)` — compute both the quotient (3) and the
; remainder (2) in a single subroutine, and return them **both** to
; the caller. The exit status is `quotient * 10 + remainder = 32`,
; which lets us see with one number that both return values
; survived the call.
;
; New in this example: returning **two** values from a subroutine.
; The System V AMD64 ABI already reserves both `rax` and `rdx` as
; return-value slots (their original purpose is the two halves of a
; 128-bit integer return); the two-return pattern uses them for two
; independent 64-bit values.
;
; Bonus: the pattern lines up beautifully with the `div`
; instruction, which computes quotient (into `rax`) and remainder
; (into `rdx`) in a single cycle — the CPU literally does the whole
; job at once, and the ABI already has a place to put both halves.

%ifdef MACOS
%define SYS_EXIT 0x2000001
%else
%define SYS_EXIT 60
%endif

default rel
global _start
global _main

section .text

_start:
_main:
    mov rdi, 17                      ; arg 1: dividend
    mov rsi, 5                       ; arg 2: divisor
    call divmod                      ; rax = 3 (quotient), rdx = 2 (remainder)

    ; Combine both returns into one exit-status number so the
    ; reader can see they both survived: 3 * 10 + 2 = 32.
    imul rax, 10
    add  rax, rdx

    mov rdi, rax                     ; arg 1: exit status = 32
    mov rax, SYS_EXIT
    syscall                          ; sys_exit(32)

; (uint64_t quotient, uint64_t remainder) divmod(uint64_t a, uint64_t b)
;   Args (System V AMD64):
;     a in rdi, b in rsi
;   Returns:
;     quotient  in rax  (primary return slot)
;     remainder in rdx  (secondary return slot)
;
; `div rsi` divides the 128-bit dividend in `rdx:rax` by `rsi`,
; leaving the quotient in `rax` and the remainder in `rdx`. Zeroing
; `rdx` first turns the 128-bit dividend into just the 64-bit value
; already in `rax` (unsigned division). Signed inputs would use
; `cqo` + `idiv` instead.
divmod:
    mov rax, rdi                     ; low 64 bits of dividend
    xor rdx, rdx                     ; high 64 bits = 0 (unsigned)
    div rsi                          ; rax = a / b, rdx = a % b
    ret
