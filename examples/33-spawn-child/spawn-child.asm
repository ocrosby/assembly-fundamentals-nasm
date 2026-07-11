; Run `/usr/bin/true` in a child process via libproc's
; `spawn_wait` composed helper, then exit 42 iff the child
; ran cleanly. This is the first example to reach into
; libproc's `util/` bucket rather than its raw syscall
; wrappers — spawn_wait folds fork + execve + wait4 into a
; single call, so the caller never has to hand-roll the
; child-vs-parent branching or the wstatus decoding.
;
; Program flow:
;
;   argv = ["/usr/bin/true", NULL]
;   envp = [NULL]
;   spawn_wait("/usr/bin/true", argv, envp)
;     ├── fork()  ────► child branch: execve(path, argv, envp)
;     │                 ├── success: kernel replaces the child's
;     │                 │            image with /usr/bin/true, which
;     │                 │            exits(0)
;     │                 └── failure: raw _exit(127) (shell "command
;     │                              not found" convention)
;     └── parent branch: wait4(child, &wstatus)
;                        returns wstatus (0 for our /usr/bin/true)
;                        — or -errno on fork/wait4 failure
;
;   parent gets wstatus == 0 → exit(42)
;   parent gets anything else → exit(1)
;
; /usr/bin/true exists on both macOS (bare `/bin` on Darwin has
; no `true`) and modern Linux (where `/bin` is a symlink to
; `/usr/bin` under usrmerge). Same portability find that the
; libproc smoke test made.

%ifdef MACOS
%define SYS_exit 0x2000001
%else
%define SYS_exit 60
%endif

default rel

extern spawn_wait

global _start
global _main

section .rodata
path:  db "/usr/bin/true", 0
argv:  dq path, 0                    ; argv[] = { path, NULL }
envp:  dq 0                          ; envp[] = { NULL } — empty env

section .text

_start:
_main:
    ; spawn_wait(path, argv, envp)
    lea rdi, [path]
    lea rsi, [argv]
    lea rdx, [envp]
    call spawn_wait
    test rax, rax
    jnz .fail                        ; wstatus != 0 or -errno

    ; Child ran cleanly. Distinguish success from a bare
    ; "exit 0" by returning 42 explicitly — the CI expected
    ; map asserts this.
    mov rax, SYS_exit
    mov edi, 42
    syscall

.fail:
    mov rax, SYS_exit
    mov edi, 1
    syscall
