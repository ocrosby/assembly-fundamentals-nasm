; resolv_conf_read_search(path: rdi, out_buf: rsi, capacity: rdx)
;     -> rax = count of domains parsed (>= 0) or negative errno
;
; Reads the resolv.conf-format file at *path* and populates
; *out_buf* with the search-domain list — each domain written
; as a NUL-terminated ASCII string, laid down back-to-back.
;
; RFC 1035 §6.1 and glibc's stub-resolver both treat the two
; directives that yield a search list as mutually exclusive
; and last-write-wins:
;
;   * `search a b c`  — explicit list; every whitespace-
;                       separated field is a domain
;   * `domain a`      — legacy single-domain shorthand; the
;                       list contains exactly one entry
;
; When either directive is encountered, the search list built
; so far is discarded and rebuilt from that directive's fields.
; This mirrors what libc does — the last `search` or `domain`
; line in the file is the one that takes effect.
;
; Return convention:
;
;   count >= 0    number of domains written to out_buf.
;                 Zero means the file was well-formed but held
;                 no search / domain directive — same
;                 "empty is not an error" convention that
;                 resolv_conf_read_all uses.
;   -ENOSPC (-28) at least one domain did not fit in the
;                 caller-supplied capacity. The buffer contents
;                 up to that point are left intact for
;                 debugging but the count is negative — callers
;                 should treat -ENOSPC as "no search list".
;   -errno        file open / pread / close failure passed
;                 through unchanged.
;
; The file-read boilerplate is the same as resolv_conf_read
; and resolv_hosts_lookup: pread the whole file into a 4096-
; byte stack buffer, close, then parse. Real /etc/resolv.conf
; files are almost always under 500 bytes.

%include "syscall.inc"

default rel

extern open, pread                  ; libio
extern close                        ; libsock

global resolv_conf_read_search

section .text

%define O_RDONLY  0
%define BUF_SIZE  4096

%ifdef MACOS
%define ENOSPC_VAL 28
%else
%define ENOSPC_VAL 28
%endif

; Stack layout:
;
;   [rsp+0..7]        LINE_END_ADDR — pointer we NUL'd for the
;                                     current line; restored on
;                                     line-loop advance
;   [rsp+8]           LINE_END_BYTE
;   [rsp+9..15]       padding
;   [rsp+16..23]      OUT_BASE       — original out_buf so a
;                                     `search`/`domain` reset
;                                     restores the cursor
;   [rsp+24..31]      OUT_END        — out_buf + capacity so
;                                     the parser can bounds-
;                                     check each write
;   [rsp+32..4128]    read buffer

%define LINE_END_ADDR   0
%define LINE_END_BYTE   8
%define OUT_BASE        16
%define OUT_END         24
%define BUF_OFF         32
%define STACK_SIZE      4128

; Register roles:
;   r12 = read-buffer base
;   r13 = read cursor
;   r14 = read-buffer end (base + bytes_read)
;   r15 = write cursor (into caller's out_buf; advances per
;         copied byte)
;   rbp = fd during open/pread/close, then MATCH_COUNT (u32)
;   rbx = OVERFLOW flag (0 = ok, 1 = we ran out of capacity;
;         set once, checked at return so a partial overflow
;         translates to -ENOSPC)

resolv_conf_read_search:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, STACK_SIZE

    mov r15, rsi                    ; write cursor = out_buf
    mov [rsp + OUT_BASE], rsi
    lea rax, [rsi + rdx]            ; out_end = out_buf + capacity
    mov [rsp + OUT_END], rax
    lea r12, [rsp + BUF_OFF]
    xor ebx, ebx                    ; overflow flag = 0

    ; --- open(path, O_RDONLY, 0) ---
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .done
    mov rbp, rax                    ; fd

    ; --- pread(fd, buf, BUF_SIZE, 0) ---
    mov rdi, rbp
    mov rsi, r12
    mov edx, BUF_SIZE
    xor ecx, ecx
    call pread
    test rax, rax
    js .close_and_fail
    jz .empty_close                 ; empty file → count = 0
    lea r14, [r12 + rax]

    ; --- close(fd) — parsing is buffer-local ---
    mov rdi, rbp
    call close

    ; Repurpose rbp as MATCH_COUNT (u64).
    xor ebp, ebp
    mov r13, r12

.next_line:
    cmp r13, r14
    jae .end_of_data

    ; Find end of this line (LF or buffer end).
    mov rcx, r13
.find_lf:
    cmp rcx, r14
    jae .line_end
    cmp byte [rcx], 10
    je .line_end
    inc rcx
    jmp .find_lf
.line_end:

    ; NUL-terminate the line so the string comparisons stop
    ; at the boundary. Save the byte we clobber so the LF
    ; still terminates the loop.
    mov al, [rcx]
    mov [rsp + LINE_END_BYTE], al
    mov [rsp + LINE_END_ADDR], rcx
    mov byte [rcx], 0

    call .try_line

    mov rcx, [rsp + LINE_END_ADDR]
    mov dl, [rsp + LINE_END_BYTE]
    mov [rcx], dl

    ; .try_line does not signal via rax; it either mutated
    ; r15 (wrote entries) or left it alone. Advance the outer
    ; cursor and loop.
    cmp rcx, r14
    jae .end_of_data
    lea r13, [rcx + 1]
    jmp .next_line

.end_of_data:
    ; Overflow trumps a successful partial parse — return
    ; -ENOSPC so callers know the list is incomplete.
    test ebx, ebx
    jnz .overflow
    mov rax, rbp                    ; count
    jmp .done

.empty_close:
    mov rdi, rbp
    call close
    xor eax, eax                    ; count = 0
    jmp .done

.close_and_fail:
    push rax
    mov rdi, rbp
    call close
    pop rax
    jmp .done

.overflow:
    mov rax, -ENOSPC_VAL

.done:
    add rsp, STACK_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- .try_line -----------------------------------------------
; Parses one NUL-terminated line at r13. If it starts with a
; `search` or `domain` keyword, resets the write cursor and
; MATCH_COUNT, then copies each whitespace-separated field to
; the out_buf as a NUL-terminated string. Non-matching lines
; leave the state alone.
;
; State touched:
;   * r15 may be reset to OUT_BASE and re-advanced.
;   * rbp (MATCH_COUNT) may be reset to 0 and re-incremented.
;   * ebx (OVERFLOW flag) may be set to 1 if the write cursor
;     hits OUT_END mid-copy. The remaining fields on this line
;     are still walked so the parser state stays consistent,
;     but no further bytes are written.
;
; Uses r8 = line walker, rcx/rdx = scratch, rax = keyword
; comparator. Preserves r12/r13/r14/r15 for the outer.
.try_line:
    push r12
    push r13

    mov r8, r13                     ; walker

    ; Strip a '#' comment if present.
    mov rax, r8
.strip_comment:
    mov cl, [rax]
    test cl, cl
    jz .strip_done
    cmp cl, '#'
    je .cut
    inc rax
    jmp .strip_comment
.cut:
    mov byte [rax], 0
.strip_done:

    ; Skip leading whitespace.
    call .skip_ws
    mov cl, [r8]
    test cl, cl
    jz .no_match

    ; Try "search" first, then "domain". Both reset state.
    lea rax, [rel kw_search]
    call .kw_cmp
    test eax, eax
    jnz .directive_match

    lea rax, [rel kw_domain]
    call .kw_cmp
    test eax, eax
    jz .no_match

.directive_match:
    ; r8 now points at the character just past the keyword.
    ; That character must be whitespace (i.e. the keyword must
    ; be a full token, not a prefix of some other word).
    mov cl, [r8]
    cmp cl, ' '
    je .after_kw
    cmp cl, 9
    je .after_kw
    jmp .no_match

.after_kw:
    ; Reset the search list — last directive wins.
    ; Inside .try_line after push r12; push r13 the outer frame
    ; lives at [rsp + 24 + …]: retaddr(8) + r12(8) + r13(8) = 24.
    mov r15, [rsp + 24 + OUT_BASE]
    xor ebp, ebp

.next_field:
    call .skip_ws
    mov cl, [r8]
    test cl, cl
    jz .no_match                    ; nothing left on the line

    ; Copy this field (up to whitespace or NUL) to [r15],
    ; then append a NUL terminator. Bump MATCH_COUNT.
    call .copy_field
    inc rbp
    jmp .next_field

.no_match:
.try_done:
    pop r13
    pop r12
    ret

; ---- .kw_cmp ------------------------------------------------
; Compares the C-string at rax against the walker at r8. On
; match, returns eax=1 with r8 advanced past the matched
; keyword. On mismatch, returns eax=0 and r8 unchanged.
.kw_cmp:
    push r9
    push r10
    mov r9, r8                      ; walker
    mov r10, rax                    ; kw pointer
.kw_loop:
    mov cl, [r10]
    test cl, cl
    jz .kw_matched
    mov dl, [r9]
    cmp cl, dl
    jne .kw_mismatch
    inc r9
    inc r10
    jmp .kw_loop
.kw_matched:
    mov r8, r9
    mov eax, 1
    pop r10
    pop r9
    ret
.kw_mismatch:
    xor eax, eax
    pop r10
    pop r9
    ret

; ---- .copy_field --------------------------------------------
; Copies bytes from [r8] until whitespace or NUL, appending a
; final NUL byte to [r15]. On overflow (would write past
; OUT_END), sets ebx = 1 and returns without writing further
; bytes — but still advances r8 past the field so the parser
; can continue walking the line.
.copy_field:
    ; Inside .copy_field (called from .try_line) the outer
    ; frame sits at [rsp + 32 + …]: retaddr(8) + r12(8) + r13(8)
    ; from .try_line's prologue, plus retaddr(8) from this call.
    mov rax, [rsp + 32 + OUT_END]
.copy_byte:
    mov cl, [r8]
    test cl, cl
    jz .copy_terminate
    cmp cl, ' '
    je .copy_terminate
    cmp cl, 9
    je .copy_terminate
    ; Would this write exceed capacity?
    cmp r15, rax
    jae .set_overflow
    mov [r15], cl
    inc r15
    inc r8
    jmp .copy_byte
.copy_terminate:
    ; Append NUL. Check room for the terminator too.
    cmp r15, rax
    jae .set_overflow
    mov byte [r15], 0
    inc r15
    ret
.set_overflow:
    mov ebx, 1
    ; Advance r8 past the rest of this field so the outer
    ; loop can continue to .next_field cleanly.
.drain_field:
    mov cl, [r8]
    test cl, cl
    jz .drained
    cmp cl, ' '
    je .drained
    cmp cl, 9
    je .drained
    inc r8
    jmp .drain_field
.drained:
    ret

; ---- .skip_ws -----------------------------------------------
.skip_ws:
    mov cl, [r8]
    cmp cl, ' '
    je .skip_ws_step
    cmp cl, 9
    je .skip_ws_step
    ret
.skip_ws_step:
    inc r8
    jmp .skip_ws

section .rodata
kw_search: db "search", 0
kw_domain: db "domain", 0
