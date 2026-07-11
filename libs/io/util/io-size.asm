; io_size(fd, out_size_ptr) -> rax = 0 or -errno
;
; Portable file-size extraction. Calls fstat internally,
; extracts the platform-appropriate st_size field, and stores
; it as a signed 64-bit integer at *out_size_ptr*. Callers
; never need to know the per-platform struct offset.
;
; Motivation: the common "read the whole file into a buffer"
; pattern needs the file size up front. Doing that from a
; NASM caller would otherwise require declaring the stat
; buffer, calling fstat, and knowing that ST_SIZE_OFF is 96
; on macOS but 48 on Linux. This helper hides the layout
; entirely.
;
; Stack frame:
;
;   [rsp+0..7]     saved rbx (out_size_ptr across the fstat call)
;   [rsp+8..151]   144-byte stat scratch buffer
;
; Total: 152 bytes. rsp on entry is misaligned by 8 (call
; pushed the return address); push rbx makes it aligned;
; sub rsp, 144 keeps it aligned (144 mod 16 = 0). The call
; to fstat therefore lands on an aligned rsp.

%include "syscall.inc"

default rel

extern fstat

global io_size

section .text

io_size:
    push rbx
    sub rsp, STATBUF_SIZE
    mov rbx, rsi                    ; save caller's out pointer

    ; fstat(fd=rdi (unchanged), buf=rsp)
    mov rsi, rsp
    call fstat
    test rax, rax
    js .done                        ; -errno passes through in rax

    ; Success — copy the platform-appropriate st_size slot.
    mov rax, [rsp + ST_SIZE_OFF]
    mov [rbx], rax
    xor eax, eax                    ; return 0

.done:
    add rsp, STATBUF_SIZE
    pop rbx
    ret
