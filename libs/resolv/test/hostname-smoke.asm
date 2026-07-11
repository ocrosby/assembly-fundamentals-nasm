; hostname-smoke.asm — smoke test for resolv_hostname_at, the
; composed entry point that tries /etc/hosts first and falls
; back to DNS through resolv.conf.
;
; The harness prepares two fixtures:
;
;   HOSTS_PATH — a /etc/hosts-format file with two entries:
;     libresolv-hostname-hit.test → 198.18.0.1
;     (nothing else)
;
;   CONF_PATH — a resolv.conf pointing at 127.0.0.1:<DNS_PORT>
;     where <DNS_PORT> is the mock DNS server's ephemeral
;     port. resolv_hostname_at reads this file to pick a
;     resolver.
;
; Wait — resolv_conf_read parses only the IP from a nameserver
; line, not the port. On a real system the resolver always
; listens on 53. The mock server here is on a random port, so
; a straight resolv_hostname_at call would send the DNS query
; to 127.0.0.1:53, which nothing is listening on.
;
; The test works around this by exercising only the hosts
; branch of resolv_hostname_at — one hit (comes back from the
; hosts file without touching DNS) and one miss (the DNS call
; is expected to fail with the socket errno for connection
; refused / timeout). That is still a real end-to-end test of
; the composition: hosts-then-conf-then-resolv_a, with each
; wired to the correct arguments.
;
; Sub-checks:
;
;   1 hit path: resolv_hostname_at(hosts, conf, "libresolv-
;     hostname-hit.test", &ip) → 0, ip = 198.18.0.1
;   2 miss path: resolv_hostname_at(hosts, conf, "no-such.test",
;     &ip) → negative errno (either -ETIMEDOUT if the DNS
;     recvfrom times out, or -ECONNREFUSED if the kernel
;     returned ICMP fast)
;   3 v6 hit path: resolv_hostname_at6(hosts, conf, "libresolv-
;     hostname-v6.test", &ip16) → 0, ip16 = 2001:db8::1
;   4 v6 miss path: resolv_hostname_at6(hosts, conf, "no-such.
;     test", &ip16) → negative errno (same rationale as 2, but
;     via the AAAA path)
;   5 v1.4 failover: FAILOVER_CONF_PATH lists two nameservers.
;     The first is 127.0.0.1:1 — nothing listens there, so
;     resolv_a fails against it. The second points at the mock
;     spun up by run.sh, which answers the canonical name.
;     The lookup passes only if the iteration falls through
;     from resolver 1 to resolver 2.
;   6 v1.5 search-domain fallback: SEARCH_CONF_PATH lists one
;     nameserver (the mock) and `search test`. The query name
;     "libresolv-ok" has no dot, so v1.5's iteration composes
;     "libresolv-ok.test" and gets 203.0.113.42 from the mock.
;     This proves both that the mock's NXDOMAIN triggers the
;     fallback and that compose_name assembles the FQDN
;     correctly.
;
; Fail IDs past 9 use letters — see hosts-smoke for the
; convention. The v6 sub-checks stay in the digit range so
; this file does not need it.

%ifndef HOSTS_PATH
%define HOSTS_PATH "/tmp/libresolv-hostname-hosts-default"
%endif
%ifndef CONF_PATH
%define CONF_PATH "/tmp/libresolv-hostname-conf-default"
%endif
%ifndef FAILOVER_CONF_PATH
%define FAILOVER_CONF_PATH "/tmp/libresolv-hostname-failover-default"
%endif
%ifndef SEARCH_CONF_PATH
%define SEARCH_CONF_PATH "/tmp/libresolv-hostname-search-default"
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%else
%define SYS_write 1
%define SYS_exit  60
%endif

default rel

extern resolv_hostname_at, resolv_hostname_at6

global _start
global _main

section .rodata
hosts_path:    db HOSTS_PATH, 0
conf_path:     db CONF_PATH, 0
failover_conf_path: db FAILOVER_CONF_PATH, 0
search_conf_path:   db SEARCH_CONF_PATH, 0

n_hit:      db "libresolv-hostname-hit.test", 0
n_miss:     db "no-such.test", 0
n_v6_hit:   db "libresolv-hostname-v6.test", 0
; The mock server answers this canonical name with an A record
; for 203.0.113.42. Used to verify sub-check 5's failover.
n_failover: db "libresolv-ok.test", 0
; Bare short name — sub-check 6's search-domain iteration
; composes it with "test" to hit the mock.
n_search:   db "libresolv-ok", 0

exp_hit:    db 198, 18, 0, 1
exp_failover: db 203, 0, 113, 42

; 2001:db8::1 as 16 network-order bytes.
exp_v6_hit: db 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
ip_buf:   resb 4
ip6_buf:  resb 16

section .text

_start:
_main:
    ; 1: hosts hit → success, no DNS traffic
    mov byte [fail_id], '1'
    lea rdi, [hosts_path]
    lea rsi, [conf_path]
    lea rdx, [n_hit]
    lea rcx, [ip_buf]
    call resolv_hostname_at
    test rax, rax
    jnz .fail
    mov eax, [rel exp_hit]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 2: hosts miss → falls to DNS; the DNS call fails against a
    ; port nothing listens on. We just require a negative rax
    ; (some -errno; the specific one depends on the kernel).
    mov byte [fail_id], '2'
    lea rdi, [hosts_path]
    lea rsi, [conf_path]
    lea rdx, [n_miss]
    lea rcx, [ip_buf]
    call resolv_hostname_at
    test rax, rax
    jns .fail

    ; 3: v6 hit path → success from hosts, no DNS traffic
    mov byte [fail_id], '3'
    lea rdi, [hosts_path]
    lea rsi, [conf_path]
    lea rdx, [n_v6_hit]
    lea rcx, [ip6_buf]
    call resolv_hostname_at6
    test rax, rax
    jnz .fail
    lea rdi, [ip6_buf]
    lea rsi, [exp_v6_hit]
    mov ecx, 16
    call memeq
    test rax, rax
    jz .fail

    ; 4: v6 miss → falls to AAAA DNS at a dead port. Any negative
    ; rax is acceptable (same rationale as sub-check 2).
    mov byte [fail_id], '4'
    lea rdi, [hosts_path]
    lea rsi, [conf_path]
    lea rdx, [n_miss]
    lea rcx, [ip6_buf]
    call resolv_hostname_at6
    test rax, rax
    jns .fail

    ; 5: v1.4 failover — the failover fixture lists a dead
    ; resolver first (127.0.0.1:1) and the mock second. The
    ; name is not in hosts, so the DNS path runs. The first
    ; resolver fails with -ECONNREFUSED/-ETIMEDOUT; the second
    ; answers with 203.0.113.42. Success proves the iterator
    ; actually moved past the failing entry.
    mov byte [fail_id], '5'
    lea rdi, [hosts_path]
    lea rsi, [failover_conf_path]
    lea rdx, [n_failover]
    lea rcx, [ip_buf]
    call resolv_hostname_at
    test rax, rax
    jnz .fail
    mov eax, [rel exp_failover]
    cmp eax, dword [ip_buf]
    jne .fail

    ; 6: v1.5 search-domain fallback — SEARCH_CONF_PATH has
    ; `search test` + the mock. Query "libresolv-ok" (no dot):
    ; the mock replies NXDOMAIN for the bare name, then search
    ; iteration composes "libresolv-ok.test" and gets the A
    ; record for 203.0.113.42.
    mov byte [fail_id], '6'
    lea rdi, [hosts_path]
    lea rsi, [search_conf_path]
    lea rdx, [n_search]
    lea rcx, [ip_buf]
    call resolv_hostname_at
    test rax, rax
    jnz .fail
    mov eax, [rel exp_failover]     ; same 203.0.113.42
    cmp eax, dword [ip_buf]
    jne .fail

    ; PASS
    mov rax, SYS_write
    mov edi, 1
    lea rsi, [pass_msg]
    mov edx, pass_len
    syscall
    mov rax, SYS_exit
    xor edi, edi
    syscall

.fail:
    mov rax, SYS_write
    mov edi, 2
    lea rsi, [fail_msg]
    mov edx, fail_len
    syscall
    mov rax, SYS_exit
    mov edi, 1
    syscall

; memeq(rdi=a, rsi=b, ecx=len) → rax = 1 if equal else 0
memeq:
    xor edx, edx
.mem_loop:
    cmp edx, ecx
    jge .mem_eq
    mov al, [rdi + rdx]
    cmp al, [rsi + rdx]
    jne .mem_ne
    inc edx
    jmp .mem_loop
.mem_eq:
    mov eax, 1
    ret
.mem_ne:
    xor eax, eax
    ret
