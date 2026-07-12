; file_read_all(path, out_addr, out_size) -> 0 or -errno
;
; "Give me this entire file as one contiguous buffer" — the
; standard config-parser / firmware-loader entry point built
; on top of libio's `open`, `io_size`, `mmap`, and a raw
; close syscall.
;
; Program flow:
;
;   open(path, O_RDONLY, 0)                       → fd
;   io_size(fd, out_size)                         → *out_size = filesize
;   if size == 0:
;       *out_addr = NULL
;       close(fd)
;       return 0
;   addr = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0)
;   close(fd)         ; mapping outlives the fd on both platforms
;   *out_addr = addr
;   return 0
;
; The fd is closed as soon as the mapping is established.
; POSIX mmap semantics keep the mapping alive after the
; underlying fd is closed on both macOS and Linux — the
; kernel holds an internal reference to the vnode. Callers
; therefore never see an open fd for the file, only the
; PROT_READ view.
;
; Ownership contract: the caller owns the returned mapping
; and is responsible for calling munmap(addr, size) when
; done. libio does not attach a finalizer or track the
; allocation.
;
; Zero-length files: `*out_addr` is written as NULL and
; `*out_size` as 0. mmap(len=0) is EINVAL on Linux and
; awkward on macOS; this convention avoids the platform
; wart and gives callers a clear "empty file" sentinel.
;
; MAP_PRIVATE + PROT_READ is the intentional choice. The
; caller sees the file's byte-for-byte contents; writes into
; the mapping would be copy-on-write to a private page and
; not persist to disk — which is what a "read all" API
; wants. If the underlying file is truncated or replaced
; after this call returns, subsequent reads through the
; mapping may raise SIGBUS; callers who need snapshot
; semantics under contention should copy the bytes out
; before yielding.
;
; No libstr or libsock coupling. `close` is inlined via raw
; syscall the same way `file_copy` and `dir_iter_close` do —
; `close` is a libsock export in this repo's layout and
; pulling libsock in for one syscall would push libio's dep
; graph the wrong direction.
;
; Callee-saved registers used:
;   rbx  fd (u32 in low bits)
;   r12  out_addr pointer (also serves as scratch to hold
;        -errno across the close syscall on error paths)
;   r13  out_size pointer

%include "syscall.inc"

%define O_RDONLY 0

%ifdef MACOS
%define SYS_close 0x2000006
%else
%define SYS_close 3
%endif

default rel

extern open, mmap
extern io_size

global file_read_all

section .text

file_read_all:
    push rbx
    push r12
    push r13
    ; 3 pushes = 24 bytes; entry rsp%16 = 8 → post-push rsp%16 = 0,
    ; aligned for calls.

    mov r12, rsi                    ; save out_addr pointer
    mov r13, rdx                    ; save out_size pointer

    ; ---- open(path, O_RDONLY, 0) ----
    ; rdi already = path.
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .done                        ; nothing opened; return -errno
    mov ebx, eax                    ; fd

    ; ---- io_size(fd, out_size) ----
    ; Writes the file size directly into the caller's out
    ; slot — no intermediate stack scratch needed.
    mov edi, ebx
    mov rsi, r13
    call io_size
    test rax, rax
    js .close_fd

    ; ---- Zero-length short-circuit ----
    ; Empty file → *out_addr = NULL, *out_size already 0,
    ; close the fd, return 0.
    cmp qword [r13], 0
    jne .do_mmap
    mov qword [r12], 0
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    xor eax, eax
    jmp .done

.do_mmap:
    ; ---- mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0) ----
    xor edi, edi
    mov rsi, [r13]                  ; length
    mov edx, PROT_READ
    mov ecx, MAP_PRIVATE
    mov r8d, ebx                    ; fd
    xor r9d, r9d                    ; offset = 0
    call mmap
    test rax, rax
    js .close_fd
    mov [r12], rax                  ; store addr into caller's slot

    ; ---- close(fd) — mapping outlives the fd ----
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    xor eax, eax                    ; return 0
    jmp .done

.close_fd:
    ; -errno already in rax. r12 (out_addr pointer) is no
    ; longer needed on the error path — reuse it as scratch
    ; to preserve the errno across the raw close syscall.
    mov r12, rax
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    mov rax, r12
    ; fall through

.done:
    pop r13
    pop r12
    pop rbx
    ret
