; resolv_conf_read    (path: rdi, out_ip: rsi)
; resolv_conf_read_all(path: rdi, out_buf: rsi, max_count: rdx)
;     -> rax = 0 / count / negative errno
;
; Reads the /etc/resolv.conf-format file at *path* and returns
; nameserver directives:
;
;   resolv_conf_read     — first parseable nameserver only;
;                          writes its 4-byte IPv4 address (net
;                          order) to *out_ip*. Any :port
;                          suffix is discarded. Returns 0 on
;                          success, -ENOENT on no match,
;                          negative errno on file error.
;
;   resolv_conf_read_all — every parseable nameserver, packed
;                          into *out_buf* as consecutive 8-byte
;                          entries:
;
;                            offset 0..3  u32  IPv4 net order
;                            offset 4..5  u16  port host order
;                            offset 6..7  u16  reserved (0)
;
;                          Returns count copied (0..max_count).
;                          Zero means the file was well-formed
;                          but held no parseable nameserver
;                          directive — same signal as
;                          resolv_conf_read's -ENOENT, but the
;                          _all convention is 0-on-empty because
;                          "no entries" is the natural fold of a
;                          count-return contract. Negative rax
;                          is a syscall errno passed through.
;
; Both entry points share the parser via a mode flag on the
; stack; adding a directive to the parser applies to both.
;
; File format (subset supported here):
;
;   * Lines starting with '#' are comments and are skipped.
;     A '#' partway into a line ends the line's parseable
;     content, matching the /etc/hosts convention.
;   * Blank lines are skipped.
;   * A "nameserver" directive is the literal keyword
;     "nameserver" followed by ASCII whitespace and an
;     IPv4 address in dotted-decimal form, optionally followed
;     by a ':<port>' suffix (host-order 1..65535). Case
;     matches libc's behavior: keyword is case-sensitive; no
;     tolerance for "Nameserver" or "NAMESERVER".
;   * Anything else on the line after the address / port is
;     ignored.
;   * Non-IPv4 nameservers (an IPv6 literal, or a hostname to
;     be recursively resolved) are skipped — inet_pton4
;     rejects them and the parser moves to the next line.
;   * A malformed :port suffix (non-digit, port 0, port
;     > 65535) causes the whole line to be skipped.
;
; The v1.4 port suffix is an extension: real /etc/resolv.conf
; only lists a bare IP and callers assume port 53. The syntax
; is chosen so that a bare address parses as (ip, 53); an
; explicit ':port' overrides only the port.
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
global resolv_conf_read_all

section .text

%define O_RDONLY     0
%define BUF_SIZE     4096
%define DEFAULT_PORT 53

; Stack layout — split for the same reason hosts.asm splits it:
; the outer function's LINE_END_ADDR slot must not overlap with
; inet_pton4's output slot, or the pointer we save gets
; overwritten by the parsed IP and the byte-restore step blows
; up on a corrupted address.
;
;   [rsp+0 .. rsp+7]       LINE_END_ADDR
;   [rsp+8]                LINE_END_BYTE
;   [rsp+9]                MODE_FLAG   0 = _read (first-only),
;                                      1 = _read_all (populate list)
;   [rsp+10 .. rsp+15]     padding
;   [rsp+16 .. rsp+23]     ENTRY_SCRATCH — the packed
;                          8-byte entry the parser produces:
;                          [+0..3] u32 ip (net), [+4..5] u16
;                          port (host), [+6..7] u16 flags (0).
;                          _read reads only the low 4 bytes.
;   [rsp+24 .. rsp+31]     COUNT_REMAINING — for _read_all,
;                          the number of slots still free in the
;                          caller's out_buf. _read leaves this
;                          zero and never reads it.
;   [rsp+32 .. rsp+4128]   read buffer

%define LINE_END_ADDR    0
%define LINE_END_BYTE    8
%define MODE_FLAG        9
%define IP_SCRATCH       16          ; overall entry base (kept name
                                     ; for source diff continuity)
%define ENTRY_IP_OFF     16
%define ENTRY_PORT_OFF   20
%define ENTRY_FLAGS_OFF  22
%define COUNT_REMAINING  24
%define BUF_OFF          32
%define STACK_SIZE       4128

; Register roles:
;   r12 = buffer base
;   r13 = cursor
;   r14 = end of data
;   r15 = out cursor:
;         - _read: fixed at caller's out_ip (only ever written
;                  once on hit).
;         - _read_all: advances by 8 after every successful
;                      parse.
;   rbp = saved fd during open/pread/close, then dead. Reused
;         for MATCH_COUNT during the parse loop so the return
;         value is one register mov away.
;
; Two entry points share the parser via `conf_body`. r10b holds
; the mode flag (0 = _read, 1 = _read_all) at entry; r11d holds
; the max_count for _read_all (ignored for _read). Both are
; caller-saved but not touched between the initial mov and the
; spill to the stack inside the body — see the analogous
; comment in hosts.asm about NASM local-label anchoring.

resolv_conf_read:
    xor r10d, r10d                  ; mode = read-first-only
    xor r11d, r11d                  ; max_count unused
    jmp conf_body

resolv_conf_read_all:
    mov r10d, 1                     ; mode = read-all
    mov r11, rdx                    ; max_count (u64)

conf_body:
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, STACK_SIZE

    mov [rsp + MODE_FLAG], r10b
    mov [rsp + COUNT_REMAINING], r11
    mov r15, rsi                    ; out cursor (advances in _all)
    lea r12, [rsp + BUF_OFF]
    ; rbp holds the fd through open/pread/close; it becomes
    ; MATCH_COUNT once we enter the parse loop (see .parse_start
    ; below). Do NOT clear rbp here — the open() return value
    ; goes into it.

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

    ; From here on rbp is repurposed as the MATCH_COUNT
    ; accumulator (see register-roles comment above). The fd
    ; is no longer needed.
    xor ebp, ebp
    mov r13, r12

.next_line:
    cmp r13, r14
    jae .end_of_data                ; buffer exhausted — mode picks rax

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
    mov [rsp + LINE_END_BYTE], al
    mov [rsp + LINE_END_ADDR], rcx
    mov byte [rcx], 0

    ; Try to match "nameserver <ip>".
    call .try_line
    mov r8d, eax                    ; save verdict

    ; Restore the byte we clobbered. Use dl not al — using al
    ; would overwrite the low byte of rax, which .try_line
    ; returned as our match verdict and we test just below.
    mov rcx, [rsp + LINE_END_ADDR]
    mov dl, [rsp + LINE_END_BYTE]
    mov [rcx], dl

    test r8d, r8d
    jnz .hit

.advance_line:
    ; Advance past LF (or to EOF).
    cmp rcx, r14
    jae .end_of_data
    lea r13, [rcx + 1]
    jmp .next_line

.hit:
    ; ENTRY_SCRATCH now holds the parsed 8-byte entry. Dispatch
    ; on MODE_FLAG.
    cmp byte [rsp + MODE_FLAG], 0
    jne .hit_all

    ; _read mode: copy the u32 IP only, return 0. First hit wins.
    mov eax, [rsp + ENTRY_IP_OFF]
    mov [r15], eax
    xor eax, eax
    jmp .done

.hit_all:
    ; _read_all mode: copy the full 8-byte entry, advance cursor,
    ; increment MATCH_COUNT, keep scanning until max_count hits
    ; zero or the file ends.
    mov rax, [rsp + ENTRY_IP_OFF]   ; 8 bytes at once
    mov [r15], rax
    add r15, 8
    inc rbp                         ; MATCH_COUNT
    dec qword [rsp + COUNT_REMAINING]
    jz .end_of_data                 ; buffer full — stop
    jmp .advance_line

.end_of_data:
    ; End of file. Mode picks the return code.
    cmp byte [rsp + MODE_FLAG], 0
    je .miss                        ; _read: no match → -ENOENT
    mov rax, rbp                    ; _read_all: return count
    jmp .done

.miss:
    mov rax, -2                     ; -ENOENT
    jmp .done

.miss_close:
    mov rdi, rbp
    call close
    ; _read → -ENOENT, _read_all → 0. Both are represented by
    ; "no match" here.
    cmp byte [rsp + MODE_FLAG], 0
    je .miss_close_first
    xor eax, eax
    jmp .done
.miss_close_first:
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
;   "nameserver <ipv4>[:port]"
; writes the parsed entry into ENTRY_SCRATCH on the outer's
; frame ([r12+0..3] = IP net, [+4..5] = port host, [+6..7] = 0)
; and returns rax = 1. Otherwise returns rax = 0.
;
; The outer's .hit handler copies from ENTRY_SCRATCH into the
; caller's out_ip / out_buf; whether we're in _read or
; _read_all mode is invisible here.
;
; Local stack slot at [rsp+0] holds the colon address (0 if no
; ':port' present) so the port parse can find its start after
; the IP portion has been NUL-split.
.try_line:
    push r12
    push r13
    sub rsp, 8                      ; local: colon_addr (or 0)

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

    ; The next field is "ip[:port]<ws|NUL>". Find its end
    ; (whitespace or NUL) into r9. Save the boundary byte so
    ; we can restore it, then NUL-terminate.
    mov r9, r12
.find_field_end:
    mov cl, [r9]
    test cl, cl
    jz .field_at_end
    cmp cl, ' '
    je .field_at_end
    cmp cl, 9
    je .field_at_end
    inc r9
    jmp .find_field_end
.field_at_end:
    mov r10b, [r9]                  ; save boundary byte
    mov r11, r9                     ; save its address
    mov byte [r9], 0

    ; Scan [r12..r11) for ':'. If found, split the field at the
    ; colon so inet_pton4 sees only the IP portion, and stash
    ; the colon address in the local slot for the port-parse
    ; step below. The colon-NUL substitution is intentionally
    ; not restored — we've already finished walking this line
    ; before .next_line reads its next byte.
    mov qword [rsp + 0], 0          ; colon_addr = 0 (no colon)
    mov rcx, r12
.scan_colon:
    cmp rcx, r11
    jae .no_colon
    cmp byte [rcx], ':'
    je .found_colon
    inc rcx
    jmp .scan_colon
.found_colon:
    mov [rsp + 0], rcx              ; remember for port parse
    mov byte [rcx], 0               ; split IP off from port
.no_colon:

    ; r10 and r11 are caller-saved; stash them across the call.
    ; Two extra pushes bring the outer frame's IP_SCRATCH to
    ; [rsp + 32 + IP_SCRATCH + 16] = [rsp + 48 + IP_SCRATCH]:
    ;   3 outer pushes (rbp/r12/r13/r14/r15's first three saved
    ;   before conf_body) ... wait, the outer pushes rbp, r12,
    ;   r13, r14, r15 (5 * 8 = 40 bytes) then sub rsp, 4128.
    ;   Inside .try_line we're at return-addr(8) + push r12(8)
    ;   + push r13(8) + sub rsp,8(local slot) = 32 above the
    ;   outer's rsp. The push r10; push r11 below adds 16 more
    ;   = 48. That is the +48 you see below.
    push r10
    push r11

    mov rdi, r12
    lea rsi, [rsp + 48 + ENTRY_IP_OFF]
    call inet_pton4

    pop r11
    pop r10
    mov [r11], r10b

    test eax, eax
    jz .no_match

    ; Port: default 53, override if ':port' was seen.
    mov r10d, DEFAULT_PORT
    mov rcx, [rsp + 0]              ; colon_addr
    test rcx, rcx
    jz .have_port

    ; Parse digits at colon_addr+1 up to the NUL we wrote at
    ; r11 above. Accept 1..5 digits fitting a u16, > 0.
    inc rcx
    mov dl, [rcx]
    test dl, dl
    jz .no_match                    ; empty port field
    xor r10d, r10d                  ; accumulator
.port_digit:
    mov dl, [rcx]
    test dl, dl
    jz .port_done
    sub dl, '0'
    cmp dl, 9
    ja .no_match                    ; non-digit inside port
    imul r10d, r10d, 10
    movzx edx, dl
    add r10d, edx
    cmp r10d, 65535
    ja .no_match                    ; port out of range
    inc rcx
    jmp .port_digit
.port_done:
    test r10d, r10d
    jz .no_match                    ; port 0 rejected

.have_port:
    ; Write port + flags into the packed entry. The IP was
    ; already stored at ENTRY_IP_OFF by inet_pton4.
    ; Offsets are relative to the outer's rsp; add 32 for the
    ; three items pushed inside .try_line (retaddr + r12 + r13
    ; + the local slot).
    mov word [rsp + 32 + ENTRY_PORT_OFF], r10w
    mov word [rsp + 32 + ENTRY_FLAGS_OFF], 0
    mov eax, 1
    jmp .try_done

.no_match:
    xor eax, eax

.try_done:
    add rsp, 8                      ; release local slot
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
