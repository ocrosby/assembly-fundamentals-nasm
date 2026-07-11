; Introduce mmap by allocating an anonymous private page,
; writing a distinctive byte pattern into it, reading the same
; bytes back to verify the mapping is genuinely readable and
; writable, then releasing the page with munmap. Exit 42 on
; success (the byte we wrote and read back); exit 1 on any
; syscall error or byte mismatch.
;
; Introduces libio's memory-mapping primitives — mmap and
; munmap — via the simplest useful case: a single anonymous
; page that acts as a scratchpad the process alone can see.
;
; Every later example that needs bulk memory outside .bss
; (a large scratch buffer, a copy-on-write child page,
; shared-memory IPC between fork'd processes) builds on this
; base. The signature and error convention are identical for
; MAP_SHARED, MAP_FIXED, and file-backed mmap; only the flags
; word changes.

%ifdef MACOS
%define SYS_exit    0x2000001
; Anonymous mapping flag: Darwin picks 0x1000 for MAP_ANON,
; Linux picks 0x20. libio's syscall.inc collapses this to a
; single MAP_ANON name; here we spell it out inline to keep
; the example self-contained (no -I../../libs/io/syscall
; on the assembler line).
%define MAP_ANON    0x1000
%else
%define SYS_exit    60
%define MAP_ANON    0x20
%endif

%define PROT_READ   1
%define PROT_WRITE  2
%define MAP_PRIVATE 2
%define PAGE_SIZE   4096

default rel

extern mmap, munmap

global _start
global _main

section .text

_start:
_main:
    ; ---- mmap(NULL, 4096, PROT_R|W, MAP_ANON|MAP_PRIVATE, -1, 0) ----
    ; addr=NULL lets the kernel pick a page. fd=-1 with
    ; MAP_ANON says "no file backing, zero-fill the page".
    ; offset=0 is required for anonymous mappings.
    xor edi, edi                    ; addr = NULL
    mov esi, PAGE_SIZE
    mov edx, PROT_READ | PROT_WRITE
    mov ecx, MAP_ANON | MAP_PRIVATE
    mov r8d, -1                     ; fd = -1
    xor r9d, r9d                    ; offset = 0
    call mmap
    test rax, rax
    js .fail                        ; negative = -errno
    mov rbx, rax                    ; save mapping address

    ; ---- Write a distinctive byte to the mapping ----
    mov byte [rbx], 42

    ; ---- Read it back to prove the mapping is readable ----
    ; If mmap returned an address whose page was not actually
    ; mapped RW, this line would trigger SIGSEGV. That is the
    ; whole test — successful round trip proves the mapping is
    ; both writable and readable.
    movzx r12d, byte [rbx]

    ; ---- munmap(addr, 4096) ----
    ; Same address and length that mmap returned. Kernel
    ; releases the page; further access from this process
    ; would fault.
    mov rdi, rbx
    mov esi, PAGE_SIZE
    call munmap
    test rax, rax
    jnz .fail

    ; ---- exit(byte we read back) ----
    ; Should be 42. The CI expected-exit map asserts this to
    ; verify the whole write→read→unmap cycle ran end-to-end.
    mov rax, SYS_exit
    mov edi, r12d
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
