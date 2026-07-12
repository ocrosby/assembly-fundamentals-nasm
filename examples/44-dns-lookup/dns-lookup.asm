; First runnable that uses libresolv. Looks "localhost" up in
; /etc/hosts via `resolv_hosts_lookup`, verifies the returned
; address is `127.0.0.1`, and exits 42. No network access,
; no bind — just a purely local reader of the hosts file.
;
; libresolv also exports `resolv_a` (real DNS over UDP against
; a resolver) and `resolv_hostname_at` (reads /etc/hostname).
; This example uses the hosts-file path because it is the
; single lookup libresolv covers that is fully hermetic in
; CI: no network, no /etc dependencies beyond the OS's
; standard hosts file.
;
; Program flow:
;
;   resolv_hosts_lookup("/etc/hosts", "localhost", &out_ip)
;       → 0 on success; out_ip filled with 4 wire-order bytes
;   verify out_ip == 127.0.0.1 byte-for-byte
;   exit(42)
;
; /etc/hosts is a POSIX file present on both macOS and
; modern Linux. Every entry for "localhost" resolves to
; 127.0.0.1 by convention; if the smoke ever fails on a
; distro that ships an odd hosts file, that is a real
; environment issue and worth surfacing.

%ifdef MACOS
%define SYS_exit    0x2000001
%else
%define SYS_exit    60
%endif

default rel

extern resolv_hosts_lookup

global _start
global _main

section .rodata
path:     db "/etc/hosts", 0
name:     db "localhost", 0
; Expected wire-order bytes for 127.0.0.1.
expected: db 127, 0, 0, 1

section .bss
out_ip:   resb 4

section .text

_start:
_main:
    ; ---- resolv_hosts_lookup(path, name, &out_ip) ----
    lea rdi, [path]
    lea rsi, [name]
    lea rdx, [out_ip]
    call resolv_hosts_lookup
    test rax, rax
    jnz .fail

    ; ---- Verify the four bytes byte-for-byte ----
    mov eax, [out_ip]
    cmp eax, [expected]
    jne .fail

    ; ---- exit(42) ----
    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
