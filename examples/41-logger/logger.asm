; Real-shape logger built on libio's I/O family. Uses
; file_write_all to start a fresh log, then file_append to
; add more records — the O_TRUNC vs O_APPEND flag difference
; is what turns "replace the log" into "add to it". Reads
; the accumulated file back with file_read_all and verifies
; the exact byte sequence, then exits 42.
;
; Log records this example produces (37 bytes total):
;
;   INFO: startup\n       (14 bytes) — via file_write_all
;   WARN: slow\n          (11 bytes) — via file_append
;   ERROR: down\n         (12 bytes) — via file_append
;
; Program flow:
;
;   file_write_all(log, "INFO: startup\n", 14) → create/truncate
;   file_append(log,    "WARN: slow\n", 11)   → add
;   file_append(log,    "ERROR: down\n", 12)  → add
;   file_read_all(log, &addr, &size)          → PROT_READ view
;   assert size == 37
;   byte-compare addr against the expected concatenation
;   munmap(addr, size)
;   exit(42)
;
; Introduces:
;
; - **file_write_all + file_append composed.** file_write_all
;   is "start fresh"; file_append is "add more". Together
;   they are the whole shape of a log writer — the first
;   record establishes the file, every subsequent record
;   grows it.
; - **The full libio I/O family in one program.** After 40
;   examples, this is the first that uses `file_write_all`,
;   `file_append`, and `file_read_all` in a single flow.
;   The composition is the point.

%ifdef MACOS
%define SYS_exit    0x2000001
%else
%define SYS_exit    60
%endif

default rel

extern file_write_all, file_append, file_read_all, munmap

global _start
global _main

section .rodata
path:       db "/tmp/nasm-logger.log", 0

rec_info:   db "INFO: startup", 10
rec_info_len: equ $ - rec_info                  ; 14

rec_warn:   db "WARN: slow", 10
rec_warn_len: equ $ - rec_warn                  ; 11

rec_error:  db "ERROR: down", 10
rec_error_len: equ $ - rec_error                ; 12

expected:   db "INFO: startup", 10
            db "WARN: slow", 10
            db "ERROR: down", 10
expected_len: equ $ - expected                  ; 37

section .bss
out_addr: resq 1
out_size: resq 1

section .text

_start:
_main:
    ; ---- file_write_all — start a fresh log ----
    ; O_TRUNC inside file_write_all guarantees any previous
    ; run's contents are gone. The next two file_append
    ; calls then grow the file monotonically.
    lea rdi, [path]
    lea rsi, [rec_info]
    mov rdx, rec_info_len
    call file_write_all
    test rax, rax
    jnz .fail

    ; ---- file_append — add the second record ----
    lea rdi, [path]
    lea rsi, [rec_warn]
    mov rdx, rec_warn_len
    call file_append
    test rax, rax
    jnz .fail

    ; ---- file_append — add the third record ----
    lea rdi, [path]
    lea rsi, [rec_error]
    mov rdx, rec_error_len
    call file_append
    test rax, rax
    jnz .fail

    ; ---- file_read_all — get the accumulated file ----
    lea rdi, [path]
    lea rsi, [out_addr]
    lea rdx, [out_size]
    call file_read_all
    test rax, rax
    jnz .fail

    ; ---- Verify size ----
    cmp qword [out_size], expected_len
    jne .fail

    ; ---- Byte-compare against the expected concatenation ----
    ; Spelled out as a loop so this example does not force
    ; libstr into the link line — the point of the example
    ; is libio's I/O family, not libstr's memcmp.
    mov rbx, [out_addr]                         ; mapping base
    lea r10, [expected]
    xor rcx, rcx
.cmp_loop:
    mov al, [rbx + rcx]
    cmp al, [r10 + rcx]
    jne .fail
    inc rcx
    cmp rcx, expected_len
    jb .cmp_loop

    ; ---- munmap + exit(42) ----
    mov rdi, [out_addr]
    mov rsi, [out_size]
    call munmap
    test rax, rax
    jnz .fail

    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
