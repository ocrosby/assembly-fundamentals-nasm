; First runnable that uses libio's dir_iter_open / _next /
; _close. Creates a scratch directory in /tmp, drops three
; regular files into it, then walks the directory with the
; iterator and counts how many entries have DT_REG (regular
; file). Exits with the count (3), plus a fixed offset, so
; the exit code lands on 42 and matches the family
; convention: exit_code = 3 * 14 = 42.
;
; The 3 * 14 trick keeps the sentinel visible without
; complicating the read logic. If a future OS quirk makes
; the iterator return an unexpected number of DT_REG
; entries, the multiplier makes the deviation obvious in
; the exit code.
;
; Introduces the whole dir_iter_* API in one flow:
;
;   * dir_iter_open(iter, path) — opens the directory and
;     zeros the state buffer. The buffer lives entirely in
;     the caller's .bss.
;   * dir_iter_next(iter, name_buf, size, type_out) —
;     returns 1 while more entries are available, 0 at end,
;     negative on error. Fills name_buf with the entry
;     name and type_out with the DT_* type.
;   * dir_iter_close(iter) — closes the underlying fd.
;
; Program flow:
;
;   mkdir(scratch_path, 0700)
;   for name in ["a", "b", "c"]:
;       open(scratch_path/name, O_WRONLY|O_CREAT, 0600); close
;   dir_iter_open(iter, scratch_path)
;   count = 0
;   while dir_iter_next(iter, name_buf, sizeof, &type):
;       if type == DT_REG: count += 1
;   dir_iter_close(iter)
;   ; cleanup: unlink the three files, rmdir
;   exit(count * 14)                              → 42

%include "syscall.inc"

%ifdef MACOS
%define SYS_close 0x2000006
%define SYS_exit  0x2000001
%define O_CREAT   0x0200
%else
%define SYS_close 3
%define SYS_exit  60
%define O_CREAT   0x40
%endif

%define O_WRONLY  1

default rel

extern open, mkdir, unlink, rmdir
extern dir_iter_open, dir_iter_next, dir_iter_close

global _start
global _main

section .rodata
scratch_path: db "/tmp/nasm-dir-iter", 0
file_a:       db "/tmp/nasm-dir-iter/a", 0
file_b:       db "/tmp/nasm-dir-iter/b", 0
file_c:       db "/tmp/nasm-dir-iter/c", 0

section .bss
iter:     resb DIR_ITER_SIZE
name_buf: resb 256
type:     resq 1

section .text

_start:
_main:
    ; ---- Best-effort cleanup of any leftover from a prior
    ; run. Ignore errors — a missing file is not a failure. ----
    lea rdi, [file_a]
    call unlink
    lea rdi, [file_b]
    call unlink
    lea rdi, [file_c]
    call unlink
    lea rdi, [scratch_path]
    call rmdir

    ; ---- mkdir(scratch_path, 0700) ----
    lea rdi, [scratch_path]
    mov esi, 0700q
    call mkdir
    test rax, rax
    js .fail

    ; ---- Create three empty regular files ----
    ; Each: open(path, O_WRONLY|O_CREAT, 0600); close(fd).
    ; The seeded content does not matter; only the entry
    ; type does.
    lea rdi, [file_a]
    call seed_empty_file
    test rax, rax
    js .fail

    lea rdi, [file_b]
    call seed_empty_file
    test rax, rax
    js .fail

    lea rdi, [file_c]
    call seed_empty_file
    test rax, rax
    js .fail

    ; ---- dir_iter_open(iter, scratch_path) ----
    lea rdi, [iter]
    lea rsi, [scratch_path]
    call dir_iter_open
    test rax, rax
    jnz .fail

    ; ---- Walk the directory, counting DT_REG entries ----
    xor r12d, r12d                  ; count = 0
.loop:
    lea rdi, [iter]
    lea rsi, [name_buf]
    mov edx, 256
    lea rcx, [type]
    call dir_iter_next
    test rax, rax
    js .close_fail
    jz .done_walk                   ; end of directory
    ; type is stored as a qword; only the low byte is
    ; meaningful (DT_* values fit in a nibble).
    mov al, [type]
    cmp al, DT_REG
    jne .loop
    inc r12d
    jmp .loop

.done_walk:
    ; ---- dir_iter_close ----
    lea rdi, [iter]
    call dir_iter_close
    ; ignore return; the count is what matters

    ; ---- Cleanup: unlink each file, rmdir the scratch path ----
    lea rdi, [file_a]
    call unlink
    lea rdi, [file_b]
    call unlink
    lea rdi, [file_c]
    call unlink
    lea rdi, [scratch_path]
    call rmdir

    ; ---- exit(count * 14) — should be 42 ----
    imul r12d, r12d, 14             ; r12 = count * 14
    mov edi, r12d                   ; syscall arg 1: exit code
    mov rax, SYS_exit
    syscall

.close_fail:
    ; dir_iter_next failed; close the iterator before
    ; exiting so the fd does not leak.
    lea rdi, [iter]
    call dir_iter_close
    jmp .fail

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall

; seed_empty_file(path: rdi) -> 0 on success, -errno otherwise.
; Creates *path* as an empty regular file, closes the fd.
seed_empty_file:
    push rbx
    ; open(path, O_WRONLY|O_CREAT, 0600). O_TRUNC not needed —
    ; we never write anything to the file.
    mov esi, O_WRONLY | O_CREAT
    mov edx, 0600q
    call open
    test rax, rax
    js .sef_done
    mov ebx, eax                    ; fd
    mov edi, ebx
    mov rax, SYS_close
    syscall
    xor eax, eax
.sef_done:
    pop rbx
    ret
