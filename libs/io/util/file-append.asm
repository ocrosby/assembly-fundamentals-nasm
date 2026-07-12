; file_append(path, addr, size) -> 0 or -errno
;
; Appends `size` bytes from `[addr]` to the end of the file
; at `path`, creating the file if it does not exist. The
; "add to an existing file" primitive that rounds out
; libio's I/O helper trio:
;
;   file_read_all   → read the whole file into a mapping
;   file_write_all  → replace the whole file with a buffer
;   file_append     → tack more bytes onto the tail
;   file_copy       → duplicate one file to another
;
; Program flow:
;
;   open(path, O_WRONLY|O_APPEND|O_CREAT, 0600)   → fd
;   while written < size:
;       n = write(fd, addr + written, size - written)
;       if n < 0: close(fd); return n
;       written += n
;   close(fd)
;   return 0
;
; The O_APPEND flag makes every write on this fd atomically
; seek-to-end before it writes. Multiple concurrent
; append-only writers (this process and someone else via
; the same fd or a separate open) all see interleaved but
; whole records, not stepped-on ones — this is how log
; files work.
;
; Semantics:
;   * `path` is created if missing (mode 0600). If present,
;     the write starts at the current file end — no
;     truncation.
;   * `size == 0` is legal. The routine still opens
;     (creating the file if missing) and closes; no write
;     syscall runs.
;   * Short writes are looped in userspace (matching
;     `file_write_all`'s pattern). Any error terminates the
;     loop and propagates through the close cleanup.
;
; Written as a mirror of file_write_all — the only
; differences are the flag mask (O_APPEND swaps in for
; O_TRUNC) and this header. Callee-saved register layout,
; error handling, and syscall shape are all identical.
;
; No libstr or libsock coupling. `close` is inlined via raw
; syscall the same way file_write_all, file_copy, and
; dir_iter_close do.
;
; Callee-saved registers used:
;   rbx  fd (u32 in low bits)
;   r12  addr (source pointer; reused as errno scratch on
;        the error unwind after the loop no longer needs it)
;   r13  total size
;   r14  bytes written so far

%include "syscall.inc"

%define O_WRONLY 1

%ifdef MACOS
%define O_CREAT     0x0200
%define O_APPEND    0x0008
%define SYS_write   0x2000004
%define SYS_close   0x2000006
%else
%define O_CREAT     0x40
%define O_APPEND    0x400
%define SYS_write   1
%define SYS_close   3
%endif

default rel

extern open

global file_append

section .text

file_append:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8                      ; align rsp for the open call

    mov r12, rsi                    ; save addr
    mov r13, rdx                    ; save size

    ; ---- open(path, O_WRONLY|O_APPEND|O_CREAT, 0600) ----
    ; rdi already = path.
    mov esi, O_WRONLY | O_APPEND | O_CREAT
    mov edx, 0600q
    call open
    test rax, rax
    js .done                        ; nothing opened; return -errno
    mov ebx, eax                    ; fd

    xor r14, r14                    ; bytes written so far

.write_loop:
    ; Done when written == size. Handles size == 0 on the
    ; very first iteration (no write syscall runs).
    cmp r14, r13
    je .close_ok

    ; ---- write(fd, addr + written, remaining) ----
    mov edi, ebx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14                    ; remaining bytes
    mov rax, SYS_write
    SYSCALL_NORM
    test rax, rax
    js .close_err

    add r14, rax                    ; advance by however many landed
    jmp .write_loop

.close_ok:
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    xor eax, eax                    ; return 0
    jmp .done

.close_err:
    ; -errno in rax. r12 (addr) is no longer needed; reuse
    ; it as scratch to hold the errno across the raw close.
    mov r12, rax
    mov edi, ebx
    mov rax, SYS_close
    SYSCALL_NORM
    mov rax, r12
    ; fall through

.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
