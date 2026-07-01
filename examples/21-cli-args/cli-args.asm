; Print `argv[0]` (the program's own name/path) to standard output
; and exit with `argc` as the status. Called with no extra args,
; exits 1. Called as `./cli-args foo bar`, exits 3 and prints its
; own path.
;
; New in this example: reading command-line arguments. When the
; runtime calls `main`, it hands us two values in the standard
; System V AMD64 argument registers:
;
;   `argc` in `rdi`  — the total argument count, including the
;                      program name itself.
;   `argv` in `rsi`  — a pointer to a NULL-terminated array of
;                      `char *` pointers.
;
; Layout of argv, addressed as bytes from `rsi`:
;
;   [rsi +  0]  = argv[0]    (the program name)
;   [rsi +  8]  = argv[1]    (first user-supplied arg, if any)
;   [rsi + 16]  = argv[2]
;   [rsi + 8*argc] = NULL sentinel
;
; Each argv[i] is itself a pointer to a NUL-terminated C string.
;
; This example dereferences `argv[0]` to reach the string, scans
; for its NUL to compute the length, writes the string + a newline
; to stdout, and returns `argc` as the exit status.

%ifdef MACOS
%define SYS_WRITE 0x2000004
%define MAIN_SYM  _main
%else
%define SYS_WRITE 1
%define MAIN_SYM  main
%endif

default rel
global MAIN_SYM

section .text

MAIN_SYM:
    ; Stash `argc` in `r10` before we clobber `rdi` and `rsi` with
    ; syscall args. `r10` is caller-saved and is not disturbed by
    ; the `syscall` instruction, so no push/pop is needed.
    mov r10d, edi                    ; r10 = argc

    ; Dereference argv to reach argv[0] — the program name string.
    mov rsi, [rsi]                   ; rsi = argv[0]  (char *)

    ; strlen(argv[0]) — scan forward until we hit NUL. `rdx`
    ; accumulates the length and doubles as the write-syscall's
    ; length argument when we're done.
    xor rdx, rdx
.count:
    cmp byte [rsi + rdx], 0
    je  .write
    inc rdx
    jmp .count

.write:
    ; write(stdout, argv[0], strlen(argv[0]))
    mov rax, SYS_WRITE
    mov rdi, 1                       ; fd = stdout
    ; rsi = argv[0], rdx = length — both already set
    syscall

    ; write(stdout, "\n", 1)
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [newline]
    mov rdx, 1
    syscall

    ; Return argc as the exit status. The runtime that called us
    ; will pass this to `exit()`.
    mov eax, r10d
    ret

section .rodata
newline: db 10
