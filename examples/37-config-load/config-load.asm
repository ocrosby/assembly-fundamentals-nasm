; Parse a KEY=VALUE line out of a config file using libio's
; `file_read_all` to load the file and libstr's `strchr`,
; `memcmp`, and `atoi` to walk the buffer. Exits with the
; parsed value on success (42); exits 1 on any error.
;
; This example is the first that uses two libraries together
; on the same buffer — libio hands the caller a PROT_READ view
; of the whole file, and libstr walks it byte-by-byte. It also
; demonstrates the ownership contract for `file_read_all`:
; the caller keeps the mapping alive as long as it needs the
; bytes, then `munmap(addr, size)` when done.
;
; Config format (one line, LF-terminated):
;
;   ANSWER=42\n
;
; Program flow:
;
;   Write "ANSWER=42\n" to /tmp/nasm-config.txt
;   file_read_all(path, &addr, &size)        → 0 or -errno
;   memcmp(addr, "ANSWER", 6)                → 0 (matches key)
;   strchr(addr, '=')                        → pointer to '='
;   Verify '=' sits at addr+6 (nothing between key and '=')
;   atoi(value_ptr)                          → parsed integer
;   munmap(addr, size)
;   exit(value)

%ifdef MACOS
%define SYS_write   0x2000004
%define SYS_close   0x2000006
%define SYS_exit    0x2000001
%define O_CREAT     0x0200
%define O_TRUNC     0x0400
%else
%define SYS_write   1
%define SYS_close   3
%define SYS_exit    60
%define O_CREAT     0x40
%define O_TRUNC     0x200
%endif

%define O_WRONLY     1

default rel

extern open, munmap, file_read_all
extern memcmp, strchr, atoi

global _start
global _main

section .rodata
path:     db "/tmp/nasm-config.txt", 0
key:      db "ANSWER"
key_len:  equ $ - key                   ; 6
content:  db "ANSWER=42", 10            ; 10 bytes
content_len: equ $ - content

section .bss
out_addr: resq 1
out_size: resq 1

section .text

_start:
_main:
    ; ---- Write the fixture file ----
    ; Callers reading a real config would skip this — the
    ; example seeds its own input so the whole flow runs in
    ; one process without external setup.
    lea rdi, [path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .fail
    mov ebx, eax                        ; fd

    mov edi, ebx
    lea rsi, [content]
    mov edx, content_len
    mov rax, SYS_write
    syscall
%ifdef MACOS
    jnc .write_ok
    neg rax
.write_ok:
%endif
    cmp rax, content_len
    jne .fail

    mov edi, ebx
    mov rax, SYS_close
    syscall

    ; ---- file_read_all(path, &out_addr, &out_size) ----
    lea rdi, [path]
    lea rsi, [out_addr]
    lea rdx, [out_size]
    call file_read_all
    test rax, rax
    jnz .fail

    ; ---- memcmp(addr, "ANSWER", 6) → 0 ----
    ; Confirm the buffer starts with the expected key name.
    mov r12, [out_addr]                 ; save mapping for later munmap
    mov rdi, r12
    lea rsi, [key]
    mov edx, key_len
    call memcmp
    test rax, rax
    jnz .fail

    ; ---- strchr(addr, '=') → pointer to '=' ----
    mov rdi, r12
    mov esi, '='
    call strchr
    test rax, rax
    jz .fail                            ; no '=' → malformed

    ; The '=' must sit exactly at addr + key_len (no space
    ; between key and separator). Reject anything else so the
    ; example does not silently accept "ANSWER =42".
    mov rcx, r12
    add rcx, key_len
    cmp rax, rcx
    jne .fail

    ; ---- atoi on the value ----
    ; Value starts one byte after the '=' pointer. libstr's
    ; atoi walks digits until the first non-digit (in this
    ; fixture, the trailing NUL or whatever byte the mmap
    ; landed on past the file's end) and returns the parsed
    ; integer. r13 preserves it across the munmap.
    inc rax                             ; skip past '='
    mov rdi, rax
    call atoi
    mov r13, rax                        ; save value across munmap

    ; ---- munmap(addr, size) — caller-owned cleanup ----
    mov rdi, r12
    mov rsi, [out_size]
    call munmap
    test rax, rax
    jnz .fail

    ; ---- exit(value) — should be 42 ----
    mov rax, SYS_exit
    mov edi, r13d
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
