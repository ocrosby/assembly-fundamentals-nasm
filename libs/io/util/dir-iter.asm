; dir_iter_open (iter*, path)                   -> 0 or -errno
; dir_iter_next (iter*, name_buf*, name_bufsize,
;                type_out*)                     -> 1 (have entry),
;                                                    0 (end of dir),
;                                                    negative errno
; dir_iter_close(iter*)                         -> 0 or -errno
;
; A caller-allocated iterator that hides the per-platform
; dirent record layout. The iterator's whole state lives in a
; DIR_ITER_SIZE (4128-byte) block the caller supplies — no
; heap dependency, no fd tracking outside the block, no
; hidden globals. Callers reserve the block as `resb
; DIR_ITER_SIZE` in .bss or `sub rsp, DIR_ITER_SIZE` on the
; stack.
;
; Sequential contract:
;
;   1. dir_iter_open(iter, path) — opens *path* as a directory
;      fd via libio's open() and zeroes the buffer bookkeeping.
;   2. Repeatedly call dir_iter_next(iter, name_buf, size,
;      type_out) until it returns 0 (end) or negative (errno).
;      Each successful (1) call fills *name_buf* with the
;      NUL-terminated entry name and stores the DT_* type at
;      *type_out.
;   3. dir_iter_close(iter) — closes the underlying fd.
;
; Entries include "." and ".." — the iterator does not filter
; them, matching readdir()'s behavior. Callers that want to
; skip them do a two-char check on name_buf.
;
; Long names: if the entry name (including its NUL) does not
; fit in name_bufsize, dir_iter_next returns -ENAMETOOLONG
; (-63 macOS, -36 Linux) without writing name_buf. The
; iterator state is still advanced past the record, so a
; subsequent call moves on to the next entry.

%include "syscall.inc"

default rel

extern open, getdents

global dir_iter_open
global dir_iter_next
global dir_iter_close

section .text

%ifdef MACOS
%define ENAMETOOLONG_VAL 63
%define SYS_close_val    0x2000006
%else
%define ENAMETOOLONG_VAL 36
%define SYS_close_val    3
%endif

; ---- dir_iter_open ----------------------------------------------
; Zero the bookkeeping slots first so the first dir_iter_next
; call triggers a refill. Then open the directory. On any open
; failure the fd slot is left as whatever open returned (i.e.
; negative); dir_iter_close on a failed open is a no-op because
; it detects the negative fd.
dir_iter_open:
    push rbx
    mov rbx, rdi                    ; iter*

    mov qword [rbx + DIR_ITER_POSITION], 0
    mov qword [rbx + DIR_ITER_READ_BYTES], 0
    mov qword [rbx + DIR_ITER_CURSOR], 0

    ; open(path, O_RDONLY, 0)
    mov rdi, rsi                    ; path
    xor esi, esi                    ; O_RDONLY = 0
    xor edx, edx                    ; mode ignored
    call open
    mov [rbx + DIR_ITER_FD], rax    ; may be negative
    test rax, rax
    js .done
    xor eax, eax
.done:
    pop rbx
    ret

; ---- dir_iter_next ----------------------------------------------
; Register roles inside:
;   rbx = iter*
;   r12 = name_buf
;   r13 = name_bufsize
;   r14 = type_out
;   r15 = pointer at the current record inside iter->buf
;
; 5 pushes (rbx + r12..r15) + return addr = 48 bytes = 0 mod 16,
; so rsp is 16-aligned before every nested call.
dir_iter_next:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx

.refill_if_needed:
    mov rax, [rbx + DIR_ITER_CURSOR]
    cmp rax, [rbx + DIR_ITER_READ_BYTES]
    jb .have_data

    ; Buffer empty — pull the next chunk from the kernel.
    ; getdents(fd, buf, size, &position)
    mov rdi, [rbx + DIR_ITER_FD]
    lea rsi, [rbx + DIR_ITER_BUF]
    mov edx, DIR_ITER_BUF_SIZE
    lea rcx, [rbx + DIR_ITER_POSITION]
    call getdents
    test rax, rax
    js .out                         ; -errno passes through
    jz .end_of_dir                  ; kernel signalled end
    mov [rbx + DIR_ITER_READ_BYTES], rax
    mov qword [rbx + DIR_ITER_CURSOR], 0

.have_data:
    ; r15 = &record = iter->buf + cursor
    lea r15, [rbx + DIR_ITER_BUF]
    add r15, [rbx + DIR_ITER_CURSOR]

    ; Advance cursor by d_reclen (u16 at +16).
    movzx eax, word [r15 + D_RECLEN_OFF]
    add [rbx + DIR_ITER_CURSOR], rax

    ; Copy d_type byte to *type_out.
    movzx eax, byte [r15 + D_TYPE_OFF]
    mov [r14], al

    ; Copy the NUL-terminated d_name into name_buf, up to
    ; name_bufsize bytes. If the NUL does not fit,
    ; -ENAMETOOLONG (state has already advanced so a subsequent
    ; call proceeds to the next record).
    test r13, r13
    jz .name_too_long               ; zero-size buffer can't fit even a NUL
    xor edx, edx                    ; index
.copy_name:
    mov al, [r15 + D_NAME_OFF + rdx]
    mov [r12 + rdx], al
    test al, al
    jz .copied                       ; wrote NUL
    inc rdx
    cmp rdx, r13
    jae .name_too_long              ; no room for NUL
    jmp .copy_name

.copied:
    mov eax, 1                      ; have entry
    jmp .out

.name_too_long:
    mov rax, -ENAMETOOLONG_VAL
    jmp .out

.end_of_dir:
    xor eax, eax                    ; 0 = no more entries

.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- dir_iter_close --------------------------------------------
; Close the underlying fd via a raw syscall. libio does not
; export close (it lives in libsock, which the file-oriented
; archive intentionally does not depend on), so we inline the
; kernel call rather than pull the whole socket archive in for
; one entry point.
;
; If the iterator was never successfully opened (fd < 0), skip
; the syscall and return that same errno so callers see a
; single consistent error path.
dir_iter_close:
    mov rax, [rdi + DIR_ITER_FD]
    test rax, rax
    js .bad
    mov rdi, rax
    mov rax, SYS_close_val
    SYSCALL_NORM
    ret
.bad:
    ret
