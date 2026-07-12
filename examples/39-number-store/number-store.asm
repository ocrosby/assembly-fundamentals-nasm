; End-to-end showcase for libio + libstr composition. Writes
; three decimal integers as newline-separated ASCII to a
; scratch file, reads the file back through file_read_all,
; parses each line with atoi, and exits with the running sum.
; Expected exit: 42 (12 + 13 + 17).
;
; File contents this example produces (9 bytes):
;
;   12\n13\n17\n
;
; Program flow — write phase:
;
;   itoa(12, buf + 0)             → 2 bytes at buf[0..1]
;   buf[2] = '\n'
;   itoa(13, buf + 3)             → 2 bytes at buf[3..4]
;   buf[5] = '\n'
;   itoa(17, buf + 6)             → 2 bytes at buf[6..7]
;   buf[8] = '\n'
;   file_write_all(path, buf, 9)  → 0
;
; Read + parse phase:
;
;   file_read_all(path, &addr, &size)          → PROT_READ view
;   loop 3 times:
;       n = atoi(cursor)                       ; stops at '\n'
;       sum += n
;       cursor = strchr(cursor, '\n') + 1      ; advance past LF
;   munmap(addr, size)
;   exit(sum)                                  → 42
;
; Introduces:
;
; - **itoa + atoi as a symmetric pair.** libstr v1.2's
;   conversion routines let this example serialize integers
;   to disk and reparse them without touching libc.
; - **file_write_all + file_read_all composed.** libio v1.13
;   writes the buffer; libio v1.12 hands it back. The two
;   were designed to compose — this example proves it.
; - **strchr as a line iterator.** No structural difference
;   from strchr elsewhere in libstr, but this is the first
;   example that uses it as the "advance to next line"
;   primitive that every text-format parser needs.

%ifdef MACOS
%define SYS_exit    0x2000001
%else
%define SYS_exit    60
%endif

default rel

extern file_read_all, file_write_all, munmap
extern atoi, itoa, strchr

global _start
global _main

section .rodata
path:     db "/tmp/nasm-number-store.txt", 0

; Values that sum to 42 — the sentinel exit code every mmap
; and libio example in this repo shares.
val1:     equ 12
val2:     equ 13
val3:     equ 17

section .bss
; Big enough for three two-digit integers plus their newlines
; (9 bytes) with plenty of slack.
scratch:  resb 32
out_addr: resq 1
out_size: resq 1

section .text

_start:
_main:
    ; ================================================================
    ; Write phase — build the file contents with itoa, then dump.
    ; ================================================================

    ; itoa(val1, scratch + 0) → 2
    mov rdi, val1
    lea rsi, [scratch]
    call itoa
    ; itoa's return is the byte count. r12 tracks the running
    ; write offset into scratch so the next itoa knows where
    ; to place its digits.
    mov r12, rax                    ; r12 = 2
    lea r9, [scratch]
    mov byte [r9 + r12], 10         ; '\n'
    inc r12                         ; r12 = 3

    ; itoa(val2, scratch + r12) → 2
    mov rdi, val2
    lea rsi, [scratch]
    add rsi, r12
    call itoa
    add r12, rax                    ; r12 = 5
    lea r9, [scratch]
    mov byte [r9 + r12], 10
    inc r12                         ; r12 = 6

    ; itoa(val3, scratch + r12) → 2
    mov rdi, val3
    lea rsi, [scratch]
    add rsi, r12
    call itoa
    add r12, rax                    ; r12 = 8
    lea r9, [scratch]
    mov byte [r9 + r12], 10
    inc r12                         ; r12 = 9 (total bytes)

    ; file_write_all(path, scratch, r12) → 0
    lea rdi, [path]
    lea rsi, [scratch]
    mov rdx, r12
    call file_write_all
    test rax, rax
    jnz .fail

    ; ================================================================
    ; Read + parse phase — atoi + strchr walk each line.
    ; ================================================================

    ; file_read_all(path, &out_addr, &out_size)
    lea rdi, [path]
    lea rsi, [out_addr]
    lea rdx, [out_size]
    call file_read_all
    test rax, rax
    jnz .fail

    ; rbx = cursor (walks forward); r14 = running sum.
    mov rbx, [out_addr]
    xor r14, r14

    ; Repeat three times — the file has exactly three values.
    ; Each iteration: atoi(cursor), sum += rax, cursor =
    ; strchr(cursor, '\n') + 1.
    mov r13d, 3
.parse_loop:
    mov rdi, rbx
    call atoi
    add r14, rax

    ; strchr stops at '\n' or NUL. The mmap has zero-fill
    ; past the file's end on both platforms, so a missing
    ; newline would land on NUL and produce a NULL return —
    ; but we control the file contents and every line ends
    ; with '\n', so this always finds one.
    mov rdi, rbx
    mov esi, 10                     ; '\n'
    call strchr
    test rax, rax
    jz .fail                        ; should not happen for our fixture
    lea rbx, [rax + 1]              ; advance past the newline

    dec r13d
    jnz .parse_loop

    ; ================================================================
    ; Release the mapping and exit with the sum.
    ; ================================================================

    mov rdi, [out_addr]
    mov rsi, [out_size]
    call munmap
    test rax, rax
    jnz .fail

    mov rax, SYS_exit
    mov edi, r14d                   ; sum should be 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
