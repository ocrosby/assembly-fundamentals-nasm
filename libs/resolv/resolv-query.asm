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

global resolv_query

section .text

%define AF_INET       2
%define SOCK_DGRAM    2
%define QUERY_MAX     512
%define CNAME_MAX     256
%define CNAME_HOPS    8

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
;   [2..16)    padding + resolver/port spill room
;   [16..32)   sockaddr_in
;   [32..48)   struct timeval
;   [48..64)   qtype / max_count / hop counter (spilled)
;   [64..320)  cname_buf                 ; 256 bytes
;   [320..832) query_buf                 ; 512 bytes
;   [832..1344) resp_buf                 ; 512 bytes
;   total: 1344 bytes, aligned to 16.

%define ID_OFF        0
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
%define STACK_SIZE    1360

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
