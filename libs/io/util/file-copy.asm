; file_copy(src_path, dst_path) -> 0 or -errno
;
; Copies the file at `src_path` to `dst_path` using two live
; mmap regions, matching the pattern demonstrated inline in
; [examples/35-mmap-copy](../../../examples/35-mmap-copy/) but
; folded here into a single reusable helper.
;
; Program flow:
;
;   open(src_path, O_RDONLY, 0)                      → src_fd
;   io_size(src_fd, &size)                           → size
;   open(dst_path, O_RDWR|O_CREAT|O_TRUNC, 0600)     → dst_fd
;   ftruncate(dst_fd, size)                          → zero-fill dst
;   if size == 0: skip mmap dance (see below)
;   src_map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, src_fd, 0)
;   dst_map = mmap(NULL, size, PROT_READ|PROT_WRITE,
;                  MAP_SHARED, dst_fd, 0)
;   rep movsb  ; copy `size` bytes src_map → dst_map
;   munmap(dst_map, size); munmap(src_map, size)
;   close(dst_fd); close(src_fd)
;   return 0
;
; No `read` or `write` syscall runs during the byte transfer.
; The kernel sees only the two `mmap` calls at setup, the
; destination's `MAP_SHARED` writes reaching the file on
; flush/munmap, and the closes.
;
; Zero-length source: an mmap with length 0 returns EINVAL on
; Linux and produces a zero-length mapping on macOS that is
; awkward to munmap. Both platforms handle the "just make dst
; empty" case correctly through open + ftruncate + close
; alone, so file_copy short-circuits past the mmap pair when
; size == 0.
;
; Error handling: any syscall failure returns the negative
; errno in rax, unwinding whatever state was already
; established (closes fds that were opened, unmaps regions
; that were mapped). Tail-close errors after a successful
; copy are swallowed — the bytes are already on disk via the
; MAP_SHARED writeback, so a close error there does not
; represent lost data.
;
; No libc dep, no libstr dep. `close` is inlined via raw
; syscall the same way dir_iter_close does — `close` is a
; libsock export in this repo's layout, and pulling libsock
; in for one syscall would push libio's dep graph in the
; wrong direction. `rep movsb` handles the inner copy so no
; libstr coupling appears either.
;
; Stack frame:
;
;   [rsp+0..7]     size (u64, written by io_size, read for
;                  ftruncate / mmap / rep movsb / munmap)
;   [rsp+8..15]    unused (kept for 16-byte alignment)
;
; Callee-saved registers used:
;   rbx  src_fd (u32 in low bits)
;   r12  dst_fd (u32 in low bits)
;   r13  src_map pointer
;   r14  dst_map pointer
;   r15  saved dst_path across the src open, then used as a
;        scratch across cleanup-time errno preservation

%include "syscall.inc"

%define O_RDONLY 0
%define O_RDWR   2

%ifdef MACOS
%define O_CREAT     0x0200
%define O_TRUNC     0x0400
%define SYS_close   0x2000006
%else
%define O_CREAT     0x40
%define O_TRUNC     0x200
%define SYS_close   3
%endif

default rel

extern open, ftruncate, mmap, munmap
extern io_size

global file_copy

section .text

file_copy:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16                     ; [rsp+0..7] = size scratch

    mov r15, rsi                    ; save dst_path across open(src)

    ; ---- open(src_path, O_RDONLY, 0) ----
    ; rdi already = src_path.
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .done                        ; nothing opened yet
    mov ebx, eax                    ; src_fd

    ; ---- io_size(src_fd, &size) ----
    ; io_size hides the platform-specific st_size offset;
    ; libio does the fstat internally.
    mov edi, ebx
    mov rsi, rsp
    call io_size
    test rax, rax
    js .close_src

    ; ---- open(dst_path, O_RDWR|O_CREAT|O_TRUNC, 0600) ----
    mov rdi, r15                    ; dst_path (saved above)
    mov esi, O_RDWR | O_CREAT | O_TRUNC
    mov edx, 0600q
    call open
    test rax, rax
    js .close_src
    mov r12d, eax                   ; dst_fd

    ; ---- ftruncate(dst_fd, size) ----
    mov edi, r12d
    mov rsi, [rsp]                  ; size
    call ftruncate
    test rax, rax
    jnz .close_both

    ; ---- Zero-length short-circuit ----
    cmp qword [rsp], 0
    je .success                     ; nothing to mmap; close and return 0

    ; ---- mmap(NULL, size, PROT_READ, MAP_PRIVATE, src_fd, 0) ----
    xor edi, edi
    mov rsi, [rsp]
    mov edx, PROT_READ
    mov ecx, MAP_PRIVATE
    mov r8d, ebx                    ; src_fd
    xor r9d, r9d
    call mmap
    test rax, rax
    js .close_both
    mov r13, rax                    ; src_map

    ; ---- mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED,
    ;          dst_fd, 0) ----
    xor edi, edi
    mov rsi, [rsp]
    mov edx, PROT_READ | PROT_WRITE
    mov ecx, MAP_SHARED
    mov r8d, r12d                   ; dst_fd
    xor r9d, r9d
    call mmap
    test rax, rax
    js .unmap_src_close_both
    mov r14, rax                    ; dst_map

    ; ---- rep movsb copy ----
    ; Fast-string microcoded byte copy through both mappings.
    ; No libc / libstr call — that would push libio's dep
    ; graph the wrong direction.
    mov rdi, r14                    ; dst
    mov rsi, r13                    ; src
    mov rcx, [rsp]                  ; count
    rep movsb

    ; ---- munmap(dst_map, size); munmap(src_map, size) ----
    ; Failure here is unusual (both addresses came from mmap
    ; on this same process), so return values are ignored —
    ; the bytes are already on disk via MAP_SHARED writeback.
    mov rdi, r14
    mov rsi, [rsp]
    call munmap
    mov rdi, r13
    mov rsi, [rsp]
    call munmap
    ; fall through

.success:
    ; ---- close both fds, return 0 ----
    ; Inline close via raw syscall (see file header notes).
    ; SYSCALL_NORM normalizes macOS's carry-flag error convention;
    ; return values are ignored on the happy path.
    mov edi, r12d
    mov rax, SYS_close
    SYSCALL_NORM
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    xor eax, eax                    ; return 0
    jmp .done

.unmap_src_close_both:
    ; dst mmap failed after src mmap succeeded. Save the
    ; errno, unmap the src region, then fall through to the
    ; close-both cleanup.
    mov r15, rax
    mov rdi, r13
    mov rsi, [rsp]
    call munmap
    mov rax, r15
    ; fall through

.close_both:
    ; -errno in rax. Save it, close both fds, return.
    mov r15, rax
    mov edi, r12d
    mov rax, SYS_close
    SYSCALL_NORM
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    mov rax, r15
    jmp .done

.close_src:
    ; -errno in rax. Save it, close src fd, return.
    mov r15, rax
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    mov rax, r15
    ; fall through

.done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
