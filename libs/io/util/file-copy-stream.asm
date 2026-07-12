; file_copy_stream(path, dst_fd) -> 0 or -errno
;
; Copy the entire file at `path` into an already-open fd
; `dst_fd`. Sits between `file_read_all` (source path →
; mapping) and a short-write loop that streams the bytes into
; the caller's fd. Useful for "send this file over this
; socket" patterns without materializing the bytes twice.
;
; Program flow:
;
;   file_read_all(path, &addr, &size)          → PROT_READ view
;   if size == 0: return 0                     (empty file — nothing to send)
;   while written < size:
;       n = write(dst_fd, addr + written, size - written)
;       if n < 0: munmap; return n
;       written += n
;   munmap(addr, size)
;   return 0
;
; Semantics:
;   * `path` must be readable; open failures return `-errno`
;     without touching `dst_fd`.
;   * `dst_fd` must be writable. Write errors terminate the
;     loop and propagate the negative errno through the
;     munmap cleanup.
;   * Short writes are looped in userspace matching libsock's
;     `send_all` pattern and libio's `file_write_all`.
;   * Empty source: returns 0 without any write on `dst_fd`
;     and without a munmap (file_read_all returned NULL).
;
; No libstr or libsock coupling. `write` is issued via raw
; `SYS_write` since libio does not export it (write lives in
; libsock).
;
; Callee-saved registers used:
;   rbx  dst_fd (u32 in low bits) on entry; repurposed as
;        errno scratch on the error unwind after the loop no
;        longer needs the fd
;   r12  source cursor (advances by every successful write)
;   r13  bytes remaining (decreases by every successful write)
;
; Stack layout:
;   [rsp+0..7]     out_addr slot for file_read_all
;   [rsp+8..15]    out_size slot for file_read_all

%include "syscall.inc"

%ifdef MACOS
%define SYS_write   0x2000004
%else
%define SYS_write   1
%endif

default rel

extern file_read_all, munmap

global file_copy_stream

section .text

file_copy_stream:
    push rbx
    push r12
    push r13
    sub rsp, 16                     ; 3 pushes = 24; sub 16 keeps rsp aligned

    mov ebx, esi                    ; save dst_fd

    ; ---- file_read_all(path, &out_addr, &out_size) ----
    ; rdi already = path.
    mov rsi, rsp                    ; &out_addr
    lea rdx, [rsp + 8]              ; &out_size
    call file_read_all
    test rax, rax
    js .done                        ; propagate -errno; nothing mmapped

    ; ---- Zero-length short-circuit ----
    mov r13, [rsp + 8]
    test r13, r13
    jz .done_ok                     ; addr is NULL; no munmap

    ; ---- Write loop ----
    mov r12, [rsp]                  ; source cursor
.write_loop:
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    mov rax, SYS_write
    SYSCALL_NORM
    test rax, rax
    js .unmap_err
    add r12, rax                    ; advance cursor
    sub r13, rax                    ; decrement remaining
    jnz .write_loop

    ; ---- Success cleanup: munmap and return 0 ----
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call munmap
    ; munmap failure post-success is silent — the bytes are
    ; already delivered and there is nothing meaningful the
    ; caller could do about it.

.done_ok:
    xor eax, eax                    ; return 0
    jmp .done

.unmap_err:
    ; write returned -errno. rbx (dst_fd) is no longer needed
    ; on the error path — repurpose it as scratch to preserve
    ; the errno across the munmap call.
    mov ebx, eax                    ; save errno (fits in i32)
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call munmap
    movsxd rax, ebx                 ; restore sign-extended errno

.done:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret
