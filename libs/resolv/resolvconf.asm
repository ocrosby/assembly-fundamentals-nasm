; resolv_conf_read(path: rdi, out_ip: rsi)
;     -> rax = 0 or negative errno
;
; Reads the /etc/resolv.conf-format file at *path* and writes
; the IPv4 address of the first `nameserver` directive to
; *out_ip*. Returns 0 on success, -ENOENT if the file exists
; but holds no parseable nameserver line, or the syscall's
; negative errno on file-open / file-read failure.
;
; File format (subset supported here):
;
;   * Lines starting with '#' are comments and are skipped.
;     A '#' partway into a line ends the line's parseable
;     content, matching the /etc/hosts convention.
;   * Blank lines are skipped.
;   * A "nameserver" directive is the literal keyword
;     "nameserver" followed by ASCII whitespace and an IPv4
;     address in dotted-decimal form. Case matches libc's
;     behavior: keyword is case-sensitive; there is no
;     tolerance for "Nameserver" or "NAMESERVER".
;   * Anything else on the line after the address is ignored.
;   * Non-IPv4 nameservers (an IPv6 literal, or a hostname to
;     be recursively resolved) are skipped — inet_pton4
;     rejects them and the parser moves to the next line.
;
; The first parseable nameserver wins; later ones are ignored.
; Multi-resolver failover is a v1.2 concern.
;
; Same file-reading strategy as resolv_hosts_lookup: read the
; whole file into a 4096-byte stack buffer via pread(fd, buf,
; 4096, 0), then close and parse. Real /etc/resolv.conf files
; are almost always well under 500 bytes.

%include "syscall.inc"

default rel

extern open, pread                  ; libio
extern close, inet_pton4            ; libsock

global resolv_conf_read

section .text

%define O_RDONLY   0
%define BUF_SIZE   4096

; Stack layout:
;   [rsp .. rsp+15]        scratch: parsed IP + line-end restore
;   [rsp+16 .. rsp+4112]   the 4096-byte read buffer
;   total: 4112 bytes (aligned to 16)

%define IP_SCRATCH   0
%define BUF_OFF      16
%define STACK_SIZE   4112

; Register roles:
;   r12 = buffer base
;   r13 = cursor
;   r14 = end of data
;   r15 = out_ip (survives all calls)
;   rbp = saved fd

resolv_conf_read:
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, STACK_SIZE

    mov r15, rsi                    ; out_ip
    lea r12, [rsp + BUF_OFF]

    ; open(path, O_RDONLY, 0)
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .done
    mov rbp, rax

    ; pread(fd, buf, 4096, 0)
    mov rdi, rbp
    mov rsi, r12
    mov edx, BUF_SIZE
    xor ecx, ecx
    call pread
    test rax, rax
    js .close_and_fail
    jz .miss_close                  ; empty file → -ENOENT
    lea r14, [r12 + rax]

    ; close(fd) — parsing does not need the fd anymore.
    mov rdi, rbp
    call close

    mov r13, r12

.next_line:
    cmp r13, r14
    jae .miss

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

    ; Save the terminator byte and NUL-terminate the line.
    mov al, [rcx]
    mov [rsp + IP_SCRATCH + 8], al
    mov [rsp + IP_SCRATCH], rcx
    mov byte [rcx], 0

    ; Try to match "nameserver <ip>".
    call .try_line
    mov r8d, eax                    ; save verdict

    ; Restore the byte we clobbered.
    mov rcx, [rsp + IP_SCRATCH]
    mov al, [rsp + IP_SCRATCH + 8]
    mov [rcx], al

    test r8d, r8d
    jnz .hit

    ; Advance past LF (or to EOF).
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
    mov rdi, rbp
    call close
    mov rax, -2
    jmp .done

.close_and_fail:
    push rax
    mov rdi, rbp
    call close
    pop rax

.done:
    add rsp, STACK_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ---- .try_line -----------------------------------------------
; Parses one NUL-terminated line at r13. If it matches
;   "nameserver <ipv4>"
; writes the parsed address to [r15] and returns rax = 1.
; Otherwise returns rax = 0.
.try_line:
    push r12
    push r13

    mov r12, r13                    ; walker

    ; Strip a '#' comment if present.
    mov rax, r12
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
    mov cl, [r12]
    test cl, cl
    jz .no_match

    ; Compare the leading identifier against "nameserver". No
    ; case folding — resolv.conf spec is lowercase.
    lea rax, [rel resolvconf_kw]
    mov r8, r12
.kw_cmp:
    mov cl, [rax]
    test cl, cl
    jz .kw_matched
    mov dl, [r8]
    cmp cl, dl
    jne .no_match
    inc rax
    inc r8
    jmp .kw_cmp
.kw_matched:
    ; The next character must be whitespace (i.e. keyword ends).
    mov cl, [r8]
    cmp cl, ' '
    je .kw_ws
    cmp cl, 9
    je .kw_ws
    jmp .no_match
.kw_ws:
    mov r12, r8
    call .skip_ws

    ; The next field is the IPv4 address. Find its end (whitespace
    ; or NUL), NUL-terminate, parse with inet_pton4.
    mov r9, r12
.find_ip_end:
    mov cl, [r9]
    test cl, cl
    jz .ip_at_end
    cmp cl, ' '
    je .ip_at_end
    cmp cl, 9
    je .ip_at_end
    inc r9
    jmp .find_ip_end
.ip_at_end:
    mov r10b, [r9]
    mov r11, r9
    mov byte [r9], 0

    ; r10 and r11 are caller-saved; stash them across the call.
    push r10
    push r11

    mov rdi, r12
    lea rsi, [rsp + 40 + IP_SCRATCH] ; +40 = 2 outer pushes + retaddr + 2 extra pushes
    call inet_pton4

    pop r11
    pop r10
    mov [r11], r10b

    test eax, eax
    jz .no_match

    lea rax, [rsp + 24 + IP_SCRATCH] ; two pushes + return addr
    mov r8d, [rax]
    mov [r15], r8d
    mov eax, 1
    jmp .try_done

.no_match:
    xor eax, eax

.try_done:
    pop r13
    pop r12
    ret

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

section .rodata
resolvconf_kw: db "nameserver", 0
