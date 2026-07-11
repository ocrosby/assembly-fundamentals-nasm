; Create an anonymous MAP_SHARED page in the parent, fork, and
; use that page as a one-byte IPC channel: the child writes 42
; into the page, exits, and the parent — after wait4() reaps
; the child — reads the byte back through the same mapping.
; Exit 42 on success; exit 1 on any syscall error.
;
; Third useful mmap flag combination after 30-shared-mapping's
; MAP_PRIVATE anon and 31-mmap-file's PROT_READ MAP_PRIVATE
; file-backed page: MAP_SHARED means changes made through the
; mapping are visible to every process that inherits or
; re-maps the same underlying object. When the mapping is
; created before fork, the child inherits it — and MAP_SHARED
; makes the child's writes visible in the parent's address
; space too. That is the "shared memory IPC across fork"
; pattern in its most stripped-down form.
;
; Program flow:
;
;   parent
;     mmap(NULL, 4096, PROT_READ|PROT_WRITE,
;          MAP_SHARED|MAP_ANON, -1, 0)          → shared page
;     fork() ──────┬──────────►
;                  │             child
;                  │               *(u8*)page = 42
;                  │               _exit(0)
;     wait4(child_pid, ...)
;     byte_from_child = *(u8*)page               → 42
;     munmap
;     exit(byte_from_child)                       → 42

%ifdef MACOS
%define SYS_exit    0x2000001
%define MAP_ANON    0x1000
%else
%define SYS_exit    60
%define MAP_ANON    0x20
%endif

%define PROT_READ    1
%define PROT_WRITE   2
%define MAP_SHARED   1
%define PAGE_SIZE    4096

default rel

extern mmap, munmap
extern fork, wait4

global _start
global _main

section .bss
wstatus: resd 1

section .text

_start:
_main:
    ; ---- mmap anonymous MAP_SHARED page ----
    ; Same syscall as 30-shared-mapping except MAP_SHARED
    ; replaces MAP_PRIVATE. That flag flip is the whole
    ; concept this example introduces.
    xor edi, edi                    ; addr = NULL
    mov esi, PAGE_SIZE
    mov edx, PROT_READ | PROT_WRITE
    mov ecx, MAP_SHARED | MAP_ANON
    mov r8d, -1                     ; fd = -1 (anonymous)
    xor r9d, r9d                    ; offset = 0
    call mmap
    test rax, rax
    js .fail
    mov rbx, rax                    ; save mapping address (survives fork)

    ; ---- fork() ----
    ; Both parent and child inherit rbx pointing to the
    ; same shared kernel page.
    call fork
    test rax, rax
    js .fail
    jz .child

    ; ---- Parent ----
    ; wait4 the child before reading. Once wait4 returns,
    ; the child's _exit(0) has completed, its write to the
    ; page has been flushed, and it is safe to read.
    mov r13d, eax                   ; child pid
    mov edi, r13d
    lea rsi, [wstatus]
    xor edx, edx                    ; options = 0
    xor ecx, ecx                    ; rusage = NULL
    call wait4
    test rax, rax
    js .fail

    ; Read the byte the child wrote.
    movzx r12d, byte [rbx]

    ; ---- munmap + exit ----
    mov rdi, rbx
    mov esi, PAGE_SIZE
    call munmap
    test rax, rax
    jnz .fail

    mov rax, SYS_exit
    mov edi, r12d
    syscall

.child:
    ; ---- Child ----
    ; Write byte 42 through the shared mapping. Because the
    ; kernel object behind the page is shared with the parent,
    ; the store is visible in the parent's address space too
    ; once the write completes and the child exits.
    mov byte [rbx], 42

    ; _exit(0) — do not fall through, do not call any libc.
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
