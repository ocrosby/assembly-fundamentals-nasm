; resolv_hosts_lookup(path: rdi, name: rsi, out_ip: rdx)
;     -> rax = 0 or negative errno
;
; Reads the /etc/hosts-format file at *path*, walks its lines
; looking for a hostname that matches *name* (case-insensitive),
; and writes the associated IPv4 address to *out_ip*. Same
; -errno convention every libs/ archive uses:
;
;   0             match found; out_ip populated with the four
;                 wire-order bytes of the mapped address
;   -ENOENT (-2)  file was well-formed but held no matching name
;   -errno        the open() / pread() / close() syscall failed;
;                 the wrapper's negative errno passes through
;
; File format (POSIX /etc/hosts):
;
;   * Blank lines are skipped.
;   * A '#' anywhere on a line starts a comment that runs to
;     end-of-line. The whole line is treated as if it ended at
;     the '#'.
;   * Whitespace (space and tab) separates fields. Multiple
;     whitespace characters collapse to one separator.
;   * The first field on a non-blank line is an IPv4 address in
;     dotted-decimal form; if it does not parse via
;     inet_pton4, the whole line is skipped (which covers
;     IPv6 entries transparently, since the parser rejects them).
;   * The remaining fields are the canonical hostname followed
;     by zero or more aliases. Any of them may match *name*.
;   * Hostname matching is case-insensitive on the ASCII range;
;     non-ASCII bytes compare byte-for-byte.
;
; Implementation constraints:
;
;   * The file is read whole into a 4096-byte stack buffer. If
;     the file is larger, only the first 4096 bytes are parsed
;     — matches beyond that point are missed. Real /etc/hosts
;     files are almost never that large; the DNS fallback in
;     resolv_hostname_at catches whatever is not in the buffer.
;   * No allocations. The parser walks the buffer once.
;   * Reads use pread() at offset 0 rather than lseek+read so
;     the caller's fd position is never used.
;
; Depends on libio (open, pread), libsock (close, inet_pton4).
; The archive that gets pulled in is inet_pton4 from libsock's
; inet/ subdir, plus the open/close/pread syscall wrappers.

%include "syscall.inc"

default rel

extern open, pread                  ; libio
extern close, inet_pton4            ; libsock

global resolv_hosts_lookup

section .text

%define O_RDONLY   0
%define BUF_SIZE   4096

; Register roles for the duration of the function:
;   r12  = buffer base pointer (points into stack)
;   r13  = current cursor within the buffer
;   r14  = end-of-data pointer (buf + bytes_read)
;   r15  = out_ip pointer (survives all internal calls)
;   rbx  = saved name pointer
;   rbp  = saved fd (once open succeeds)

; Stack layout:
;   [rsp .. rsp+15]        scratch: parsed IP + line-end saved offsets
;   [rsp+16 .. rsp+4112]   the 4096-byte read buffer
;   total: 4112 bytes (aligned to 16)

%define IP_SCRATCH   0
%define BUF_OFF      16
%define STACK_SIZE   4112

resolv_hosts_lookup:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, STACK_SIZE

    mov rbx, rsi                    ; name
    mov r15, rdx                    ; out_ip
    lea r12, [rsp + BUF_OFF]

    ; --- open(path, O_RDONLY, 0) ---
    ; rdi already holds path.
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .done                        ; -errno passes through
    mov rbp, rax                    ; fd

    ; --- pread(fd, buf, BUF_SIZE, 0) ---
    mov rdi, rbp
    mov rsi, r12
    mov edx, BUF_SIZE
    xor ecx, ecx                    ; offset = 0
    call pread
    test rax, rax
    js .close_and_fail              ; -errno passes through after close
    jz .miss_close                  ; 0 bytes = empty file → -ENOENT
    lea r14, [r12 + rax]

    ; --- close(fd) — no reason to hold it open through parsing ---
    mov rdi, rbp
    call close
    ; Any close error at this point is irrelevant to whether we
    ; find a match; parse the buffer regardless.

    mov r13, r12

    ; ---- Line loop ----
.next_line:
    cmp r13, r14
    jae .miss

    ; Save the byte just past the newline so we can restore it
    ; after we NUL-terminate the current line for parsing.
    ; Find end of line by scanning for LF or EOF.
    mov rcx, r13                    ; line start
.find_lf:
    cmp rcx, r14
    jae .line_terminated
    mov al, [rcx]
    cmp al, 10                      ; '\n'
    je .line_terminated
    inc rcx
    jmp .find_lf
.line_terminated:
    ; rcx now points at LF or at r14 (buffer end).

    ; Save the byte we are about to clobber and NUL-terminate.
    mov al, [rcx]
    mov [rsp + IP_SCRATCH + 8], al  ; save byte value
    mov [rsp + IP_SCRATCH], rcx     ; save its address for restore
    mov byte [rcx], 0

    ; Walk this line and try to match. r13 = start, rcx = end.
    call .try_line

    ; Restore the byte and advance past LF.
    mov rcx, [rsp + IP_SCRATCH]
    mov al, [rsp + IP_SCRATCH + 8]
    mov [rcx], al

    ; If the line matched, .try_line already wrote out_ip and
    ; returned 1 in rdi (used as a scratch flag here). Check.
    test rax, rax
    jnz .hit

    ; Advance r13 past the LF (or to EOF).
    cmp rcx, r14
    jae .miss
    lea r13, [rcx + 1]
    jmp .next_line

.hit:
    xor eax, eax
    jmp .done

.miss:
    mov rax, -2                     ; -ENOENT
    jmp .done

.miss_close:
    ; The read returned 0 but we still own the fd.
    mov rdi, rbp
    call close
    mov rax, -2
    jmp .done

.close_and_fail:
    ; pread returned an error; preserve it while closing.
    push rax
    mov rdi, rbp
    call close
    pop rax
    ; fall through

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
; Parses one NUL-terminated line at r13. Uses inet_pton4 on the
; first whitespace-delimited field, then walks the remaining
; fields comparing each case-insensitively to rbx (name). On a
; match, writes the parsed IP to [r15] and returns rax = 1.
; Otherwise returns rax = 0.
;
; Uses caller registers r13 (line start), r14 (buffer end),
; r15 (out_ip), rbx (name). Clobbers rax, rcx, rdx, rsi, rdi,
; r8, r9, r10, r11.
.try_line:
    ; Two callee-saved slots: r12 (walker inside the parser) and
    ; r13 (line start). Both are also outer-function state — we
    ; must restore them on return so the outer's line loop keeps
    ; walking. Return address + these two pushes = 24 bytes on
    ; top of the outer frame, so [rsp + 24 + IP_SCRATCH] reaches
    ; the outer's IP_SCRATCH slot.
    push r12
    push r13

    mov r12, r13                    ; walker

    ; Truncate the line at any '#' to strip comments.
    mov rax, r12
.strip_comment:
    mov cl, [rax]
    test cl, cl
    jz .comment_done
    cmp cl, '#'
    je .cut_here
    inc rax
    jmp .strip_comment
.cut_here:
    mov byte [rax], 0
.comment_done:

    ; Skip leading whitespace.
    call .skip_ws
    ; If empty after whitespace, no match.
    mov cl, [r12]
    test cl, cl
    jz .no_match

    ; The IP field runs from r12 to the next whitespace or NUL.
    ; NUL-terminate it in place, remembering the byte we clobber.
    mov r9, r12
.find_field_end:
    mov cl, [r9]
    test cl, cl
    jz .ip_terminated
    cmp cl, ' '
    je .ip_terminated
    cmp cl, 9
    je .ip_terminated
    inc r9
    jmp .find_field_end
.ip_terminated:
    mov r10b, [r9]                  ; save the byte we clobber
    mov r11, r9                     ; save the address
    mov byte [r9], 0

    ; r10 and r11 are caller-saved, and inet_pton4 will clobber
    ; both. Stash them on the stack across the call. Two extra
    ; 8-byte pushes shift the outer's IP_SCRATCH slot from
    ; [rsp+24] to [rsp+40].
    push r10
    push r11

    mov rdi, r12
    lea rsi, [rsp + 40 + IP_SCRATCH]
    call inet_pton4

    pop r11
    pop r10

    ; Restore the byte we clobbered.
    mov [r11], r10b

    test eax, eax
    jz .no_match                    ; not an IPv4 → skip line

    ; Advance past the IP field and its trailing whitespace.
    mov r12, r11
    call .skip_ws

    ; ---- Match loop: each remaining whitespace-delimited field
    ; against the caller's name. ----
.name_field:
    mov cl, [r12]
    test cl, cl
    jz .no_match

    ; Compare rbx (name) against r12 (current field), stopping
    ; at first non-match, at name's NUL, or at field's separator.
    mov rdi, rbx                    ; name walker
    mov rsi, r12                    ; field walker
.cmp_loop:
    mov al, [rdi]
    mov cl, [rsi]
    ; End-of-field on side rsi is whitespace or NUL.
    test cl, cl
    jz .field_end
    cmp cl, ' '
    je .field_end
    cmp cl, 9
    je .field_end
    ; If name reached NUL first, mismatch (name shorter than field).
    test al, al
    jz .field_mismatch
    ; Case-insensitive compare: upper→lower on both sides.
    call .tolower_al
    mov r8b, al
    mov al, cl
    call .tolower_al
    cmp r8b, al
    jne .field_mismatch
    inc rdi
    inc rsi
    jmp .cmp_loop
.field_end:
    ; Field ended. Match only if name also ended (rdi is at NUL).
    mov al, [rdi]
    test al, al
    jnz .field_mismatch
    ; --- Match found: copy the parsed IP into *out_ip. ---
    lea rax, [rsp + 24 + IP_SCRATCH] ; two pushes + return addr
    mov r8d, [rax]                  ; four wire-order bytes
    mov [r15], r8d
    mov eax, 1
    jmp .try_done

.field_mismatch:
    ; Skip to next field. Advance r12 to end of current field,
    ; then over whitespace.
.skip_field:
    mov cl, [r12]
    test cl, cl
    jz .no_match
    cmp cl, ' '
    je .after_field
    cmp cl, 9
    je .after_field
    inc r12
    jmp .skip_field
.after_field:
    call .skip_ws
    jmp .name_field

.no_match:
    xor eax, eax

.try_done:
    pop r13
    pop r12
    ret

; ---- .skip_ws -----------------------------------------------
; Advances r12 past any spaces or tabs.
.skip_ws:
    mov cl, [r12]
    cmp cl, ' '
    je .skip_ws_step
    cmp cl, 9
    je .skip_ws_step
    ret
.skip_ws_step:
    inc r12
    jmp .skip_ws

; ---- .tolower_al --------------------------------------------
; If al is an ASCII uppercase letter, converts to lowercase.
; Bytes outside 'A'..'Z' pass through unchanged.
.tolower_al:
    cmp al, 'A'
    jb .tolower_done
    cmp al, 'Z'
    ja .tolower_done
    add al, 32
.tolower_done:
    ret
