; resolv_query(name: rdi, resolver: rsi, port: rdx, qtype: rcx,
;              out_buf: r8, max_count: r9)
;     -> rax = count copied (>= 0) or negative errno
;
; The workhorse for every A / AAAA lookup libresolv performs.
; The convenience wrappers (resolv_a, resolv_aaaa, resolv_a_all,
; resolv_aaaa_all) all call this function with different qtype /
; max_count combinations.
;
; Sequence for each attempt (looped for CNAME chasing):
;
;   1  resolv_random(id_buf, 2)
;   2  resolv_encode_query(current_name, id, qtype, query_buf)
;   3  socket(AF_INET, SOCK_DGRAM, 0)
;   4  setsockopt(SO_RCVTIMEO, 5s)
;   5  sendto(fd, query, len, 0, &sa, 16)
;   6  recvfrom(fd, resp, 512, 0, NULL, NULL)
;   7  close(fd)
;   8  resolv_decode_records(resp, n, id, qtype, out_buf, max_count)
;      -> if count > 0, return count
;      -> if count < 0, return errno
;   9  resolv_decode_cname(resp, n, id, cname_buf, 256)
;      -> if -ENOENT, return -ENODATA (no A/AAAA and no CNAME)
;      -> if success, set current_name = cname_buf and re-loop
;      -> else return the decoder's error
;
; Hop limit: 8 iterations of the CNAME chase loop. Exceeding
; that returns -ELOOP.
;
; Every failure between step 3 and step 7 closes the fd before
; returning.

%include "syscall.inc"

default rel

extern resolv_random, resolv_encode_query
extern resolv_decode_records, resolv_decode_cname
extern socket, setsockopt, sendto, recvfrom, close
extern connect, send, recv

global resolv_query

section .text

%define AF_INET       2
%define SOCK_DGRAM    2
%define SOCK_STREAM   1
%define QUERY_MAX     512
%define CNAME_MAX     256
%define CNAME_HOPS    8
%define TC_FLAG_MASK  0x02          ; bit 1 of flags byte 0 (byte 2 of msg)

%ifdef MACOS
%define SIN_HEADER    0x0210
%define SOL_SOCKET    0xffff
%define SO_RCVTIMEO   0x1006
%define ELOOP_VAL     62
%else
%define SIN_HEADER    0x0002
%define SOL_SOCKET    1
%define SO_RCVTIMEO   20
%define ELOOP_VAL     40
%endif

; Register roles for the function:
;   r12   = fd (after socket succeeds)
;   r13   = out_buf (survives all calls)
;   r14   = current query id (u16 in low bits)
;   r15   = current name pointer (initially caller's name; may
;           point at cname_buf after a chase step)
;
; Stack layout (offsets from rsp):
;
;   [0..2)     id_buf                    ; 2 bytes for random ID
;                                        (repurposed by the TCP
;                                        retry as the length-
;                                        prefix scratch — the
;                                        original ID is already
;                                        in r14 by that point)
;   [2..8)     padding
;   [8..12)    resolver ip (net u32)
;   [12..14)   resolver port (host u16)
;   [16..32)   sockaddr_in
;   [32..48)   struct timeval
;   [48..64)   qtype / max_count spills
;   [64..72)   hop counter
;   [72..328)  cname_buf                 ; 256 bytes
;   [328..840) query_buf                 ; 512 bytes
;   [840..1352) resp_buf                 ; 512 bytes
;   [1352..1360) query_len (u64)         ; saved after
;                                        resolv_encode_query so
;                                        the TCP retry can
;                                        replay the same bytes
;                                        without re-encoding
;   [1360..1368) alignment padding
;
;   Total: 1368 bytes. With 6 callee-saved pushes and the
;   return address, the frame is 1368 + 48 + 8 = 1424 = 16 * 89,
;   16-byte aligned before any nested call — matching what the
;   SysV AMD64 ABI expects.

%define ID_OFF        0
%define TCP_LEN_OFF   0                  ; alias of ID_OFF; used
                                         ; by the TCP retry to
                                         ; stage the 2-byte
                                         ; big-endian length
                                         ; prefix
%define RESOLVER_OFF  8                  ; 4 bytes (net order u32)
%define PORT_OFF      12                 ; 2 bytes (host order u16)
%define SA_OFF        16
%define TV_OFF        32
%define QTYPE_OFF     48
%define MAX_COUNT_OFF 56
%define HOPS_OFF      64
%define CNAME_OFF     72
%define QUERY_OFF     328
%define RESP_OFF      840
%define QUERY_LEN_OFF 1352
%define STACK_SIZE    1368

resolv_query:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, STACK_SIZE

    ; Spill args we need to keep across many calls.
    mov r13, r8                     ; out_buf
    mov [rsp + RESOLVER_OFF], esi   ; resolver ip (u32 net)
    mov [rsp + PORT_OFF], dx        ; port (host)
    mov [rsp + QTYPE_OFF], rcx      ; qtype
    mov [rsp + MAX_COUNT_OFF], r9   ; max_count
    mov r15, rdi                    ; current_name = caller's name

    ; Initialize hop counter.
    mov qword [rsp + HOPS_OFF], CNAME_HOPS

    ; Build the sockaddr_in once — resolver / port don't change
    ; across the CNAME loop. Port swap host→net via rol.
    mov word [rsp + SA_OFF], SIN_HEADER
    mov ax, [rsp + PORT_OFF]
    rol ax, 8
    mov [rsp + SA_OFF + 2], ax
    mov eax, [rsp + RESOLVER_OFF]
    mov [rsp + SA_OFF + 4], eax
    mov qword [rsp + SA_OFF + 8], 0

    ; Set the 5-second recv timeout struct once.
    mov qword [rsp + TV_OFF], 5
    mov qword [rsp + TV_OFF + 8], 0

.attempt:
    ; Hop-limit check.
    mov rax, [rsp + HOPS_OFF]
    test rax, rax
    jz .eloop
    dec qword [rsp + HOPS_OFF]

    ; ---- 1: fresh random ID ----
    lea rdi, [rsp + ID_OFF]
    mov esi, 2
    call resolv_random
    test rax, rax
    js .early_fail
    movzx r14d, word [rsp + ID_OFF]

    ; ---- 2: encode query for current name ----
    mov rdi, r15                    ; current name
    mov rsi, r14                    ; id
    mov rdx, [rsp + QTYPE_OFF]      ; qtype (A / AAAA / …)
    lea rcx, [rsp + QUERY_OFF]
    call resolv_encode_query
    test rax, rax
    js .early_fail
    mov rbx, rax                    ; query length
    ; Save it so the TCP retry (below) can replay the same
    ; encoded bytes rather than re-run the encoder.
    mov [rsp + QUERY_LEN_OFF], rax

    ; ---- 3: socket ----
    mov edi, AF_INET
    mov esi, SOCK_DGRAM
    xor edx, edx
    call socket
    test rax, rax
    js .early_fail
    mov r12, rax                    ; fd

    ; ---- 4: setsockopt(SO_RCVTIMEO) ----
    mov rdi, r12
    mov esi, SOL_SOCKET
    mov edx, SO_RCVTIMEO
    lea rcx, [rsp + TV_OFF]
    mov r8d, 16
    call setsockopt
    test rax, rax
    js .close_and_fail

    ; ---- 5: sendto ----
    mov rdi, r12
    lea rsi, [rsp + QUERY_OFF]
    mov rdx, rbx
    xor ecx, ecx
    lea r8, [rsp + SA_OFF]
    mov r9d, 16
    call sendto
    test rax, rax
    js .close_and_fail

    ; ---- 6: recvfrom ----
    mov rdi, r12
    lea rsi, [rsp + RESP_OFF]
    mov edx, QUERY_MAX
    xor ecx, ecx
    xor r8, r8
    xor r9, r9
    call recvfrom
    test rax, rax
    js .close_and_fail
    mov rbx, rax                    ; response length

    ; ---- 7: close (ignore error) ----
    mov rdi, r12
    call close

    ; ---- 7.5: TC=1 fallback (RFC 1035 §4.2.1) ----
    ; If the response has the truncation bit set, the answer
    ; is incomplete over UDP and the client must retry over
    ; TCP. Only bother if the response is at least a full DNS
    ; header (12 bytes); anything smaller is malformed and
    ; will be rejected by the decoder anyway.
    cmp rbx, 12
    jb .decode
    test byte [rsp + RESP_OFF + 2], TC_FLAG_MASK
    jz .decode

    ; TCP retry populates RESP_OFF with the untruncated response
    ; and sets rbx to its length, or to a negative errno if
    ; anything on the TCP path failed. On error we propagate as
    ; if it were a UDP error — the caller can move on to the
    ; next resolver in the list.
    call .tcp_retry
    test rbx, rbx
    js .propagate_tcp_error

.decode:
    ; ---- 8: decode as records ----
    lea rdi, [rsp + RESP_OFF]
    mov rsi, rbx
    mov rdx, r14                    ; expected_id
    mov rcx, [rsp + QTYPE_OFF]
    mov r8, r13                     ; out_buf
    mov r9, [rsp + MAX_COUNT_OFF]
    call resolv_decode_records

    ; Positive → success. Negative except -ENODATA (which we
    ; convert from "no records" by treating count == 0 as
    ; "look for a CNAME") → propagate.
    test rax, rax
    jg .done                        ; count > 0, return it
    js .done                        ; -errno, propagate

    ; ---- 9: count == 0. Try CNAME. ----
    lea rdi, [rsp + RESP_OFF]
    mov rsi, rbx
    mov rdx, r14
    lea rcx, [rsp + CNAME_OFF]
    mov r8d, CNAME_MAX
    call resolv_decode_cname
    test rax, rax
    js .decide_no_cname

    ; Got a CNAME — chase it.
    lea r15, [rsp + CNAME_OFF]
    jmp .attempt

.decide_no_cname:
    ; If the CNAME decoder returned -ENOENT (no CNAME), we have
    ; neither an A/AAAA nor a CNAME — that's -ENODATA.
    cmp rax, -2
    jne .done                       ; other errors (badmsg, etc.)
%ifdef MACOS
    mov rax, -96
%else
    mov rax, -61
%endif
    jmp .done

.close_and_fail:
    ; Preserve errno across the close.
    mov rbx, rax
    mov rdi, r12
    call close
    mov rax, rbx
    jmp .done

.propagate_tcp_error:
    ; .tcp_retry left the errno in rbx. Surface it as rax.
    mov rax, rbx
    jmp .done

; ---- .tcp_retry ----------------------------------------------
; Refetch the current query over TCP. Uses the encoded query
; still sitting at [rsp + QUERY_OFF] and [rsp + QUERY_LEN_OFF].
;
; Inputs:  none beyond the outer frame state.
; Effects: overwrites [rsp + RESP_OFF] with the fresh answer.
; Returns: rbx = new response length OR a negative errno.
;
; On any failure the caller (resolv_query proper) drops out
; of the current attempt with .propagate_tcp_error so the
; hostname-layer resolver iterator can move to the next
; entry. Same-ID reuse is intentional: the encoded query
; still has r14's ID bytes at the start, so the server will
; mirror them back and the decoder's ID check still holds.
;
; NOTE on alignment: the outer resolv_query already has a
; 16-byte-aligned rsp before it calls .tcp_retry, but the CALL
; itself pushes 8 bytes — inside the helper rsp is misaligned
; by 8. Every subsequent `call socket` / `call setsockopt` /
; etc. would then land on a misaligned rsp, which technically
; violates the SysV AMD64 ABI (SSE-aligned code inside libc
; can fault). Fix it by reserving 8 scratch bytes at entry —
; brings rsp back to 16-aligned throughout .tcp_retry.
; NOTE: Inside .tcp_retry the outer resolv_query frame lives at
; [rsp + 16 + <offset>] — 8 bytes for the CALL retaddr plus 8
; bytes for the alignment sub_8 at entry. Use OUTER as the
; convenience macro for these accesses so a future adjustment
; changes one number rather than a dozen.
%define OUTER 16

.tcp_retry:
    sub rsp, 8
    ; ---- socket(AF_INET, SOCK_STREAM, 0) ----
    mov edi, AF_INET
    mov esi, SOCK_STREAM
    xor edx, edx
    call socket
    test rax, rax
    js .tcp_fail_nofd
    mov r12, rax                    ; TCP fd

    ; ---- setsockopt(SO_RCVTIMEO) ----
    mov rdi, r12
    mov esi, SOL_SOCKET
    mov edx, SO_RCVTIMEO
    lea rcx, [rsp + OUTER + TV_OFF]
    mov r8d, 16
    call setsockopt
    test rax, rax
    js .tcp_fail_withfd

    ; ---- connect(fd, sa, 16) ----
    mov rdi, r12
    lea rsi, [rsp + OUTER + SA_OFF]
    mov edx, 16
    call connect
    test rax, rax
    js .tcp_fail_withfd

    ; ---- build 2-byte big-endian length prefix ----
    mov rax, [rsp + OUTER + QUERY_LEN_OFF]
    mov ah, al                      ; low byte to high position
    mov al, [rsp + OUTER + QUERY_LEN_OFF + 1]
    ; ax now holds len in big-endian; the len is <= 512 so the
    ; upper 8 bits are always zero and the swap above is a
    ; correct BE16 of a u16 that fits in 9 bits.
    mov [rsp + OUTER + TCP_LEN_OFF], ax

    ; ---- send(fd, TCP_LEN_OFF, 2, 0) ----
    mov rdi, r12
    lea rsi, [rsp + OUTER + TCP_LEN_OFF]
    mov edx, 2
    call .tcp_send_all
    test rax, rax
    js .tcp_fail_withfd

    ; ---- send(fd, QUERY_OFF, query_len, 0) ----
    mov rdi, r12
    lea rsi, [rsp + OUTER + QUERY_OFF]
    mov rdx, [rsp + OUTER + QUERY_LEN_OFF]
    call .tcp_send_all
    test rax, rax
    js .tcp_fail_withfd

    ; ---- recv 2-byte length prefix ----
    mov rdi, r12
    lea rsi, [rsp + OUTER + TCP_LEN_OFF]
    mov edx, 2
    call .tcp_recv_all
    test rax, rax
    js .tcp_fail_withfd

    ; Parse BE16 length.
    movzx eax, word [rsp + OUTER + TCP_LEN_OFF]
    mov ah, al                      ; swap
    mov al, [rsp + OUTER + TCP_LEN_OFF + 1]
    movzx ebx, ax                   ; response length
    cmp ebx, QUERY_MAX
    ja .tcp_fail_badmsg              ; too large for our buf
    test ebx, ebx
    jz .tcp_fail_badmsg              ; zero-length response

    ; ---- recv the response body ----
    mov rdi, r12
    lea rsi, [rsp + OUTER + RESP_OFF]
    mov rdx, rbx
    call .tcp_recv_all
    test rax, rax
    js .tcp_fail_withfd

    ; ---- close the TCP fd, return length in rbx ----
    mov rdi, r12
    call close
    add rsp, 8                      ; release .tcp_retry's align pad
    ret

.tcp_fail_withfd:
    ; rax already holds the errno. Preserve it across close.
    mov rbx, rax
    mov rdi, r12
    call close
    mov rax, rbx
.tcp_fail_nofd:
    mov rbx, rax                    ; caller checks rbx sign
    add rsp, 8
    ret

.tcp_fail_badmsg:
    mov rdi, r12
    call close
    mov rbx, -74                    ; -EBADMSG
    add rsp, 8
    ret

; ---- .tcp_send_all -------------------------------------------
; Loop send(2) until every byte is out or an error hits.
; Inputs: rdi=fd, rsi=buf, rdx=len
; Output: rax = 0 on full send, negative errno otherwise
;
; Callee-saved r13 / r14 hold the cursor + end; 3 pushes keep
; rsp 16-aligned before every nested call (entry misalign 8
; + 3 * 8 = 32 = 0 mod 16).
.tcp_send_all:
    push rbx
    push r13
    push r14
    mov rbx, rdi                    ; fd
    mov r13, rsi                    ; cursor
    lea r14, [rsi + rdx]             ; end
.sa_loop:
    mov rax, r14
    sub rax, r13
    test rax, rax
    jz .sa_done
    mov rdi, rbx
    mov rsi, r13
    mov rdx, rax
    xor ecx, ecx                    ; flags = 0
    call send
    test rax, rax
    js .sa_fail
    add r13, rax
    jmp .sa_loop
.sa_done:
    xor eax, eax
.sa_fail:
    pop r14
    pop r13
    pop rbx
    ret

; ---- .tcp_recv_all -------------------------------------------
; Loop recv(2) until we've read len bytes or hit an error.
; A recv returning 0 means the peer closed early — treated
; as -EBADMSG.
;
; Inputs: rdi=fd, rsi=buf, rdx=len
; Output: rax = 0 on complete read, negative errno otherwise
.tcp_recv_all:
    push rbx
    push r13
    push r14
    mov rbx, rdi                    ; fd
    mov r13, rsi                    ; cursor
    lea r14, [rsi + rdx]
.ra_loop:
    mov rax, r14
    sub rax, r13
    test rax, rax
    jz .ra_done
    mov rdi, rbx
    mov rsi, r13
    mov rdx, rax
    xor ecx, ecx                    ; flags
    call recv
    test rax, rax
    js .ra_fail
    jz .ra_eof                      ; peer closed early
    add r13, rax
    jmp .ra_loop
.ra_done:
    xor eax, eax
    jmp .ra_out
.ra_eof:
    mov rax, -74                    ; -EBADMSG (short read)
    jmp .ra_out
.ra_fail:
    ; rax holds -errno already
.ra_out:
    pop r14
    pop r13
    pop rbx
    ret

.eloop:
    mov rax, -ELOOP_VAL
    jmp .done

.early_fail:
    ; Failure happened before socket() succeeded; rax already
    ; holds the negative errno.

.done:
    add rsp, STACK_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
