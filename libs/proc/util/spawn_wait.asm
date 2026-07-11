; spawn_wait(path, argv, envp) -> rax = wstatus or -errno
;
; Composed helper — fork() a child, execve() the target in the
; child, wait4() for the child in the parent, and return the
; raw wstatus so the caller can decode it with the standard
; W* macros. This is the smallest useful combination of
; libproc's syscall wrappers and doubles as the answer to
; "how do I run a program from raw assembly?".
;
; Arguments:
;   rdi = path*  NUL-terminated path to the binary — same as
;                execve's first argument.
;   rsi = argv*  NULL-terminated `char**`. Callers construct
;                this manually; the wrapper does no string
;                parsing of its own.
;   rdx = envp*  NULL-terminated `char**` for the child's
;                environment. Pass a pointer to a single
;                NULL entry for an empty environment.
;
; Return:
;   rax = wstatus     child ran; decode with WIFEXITED /
;                     WEXITSTATUS / WIFSIGNALED / WTERMSIG
;   rax = -errno      fork() itself failed (out of process
;                     table slots, resource limits, etc.), or
;                     wait4() failed (should not happen — the
;                     immediate child is always waitable — but
;                     the errno is passed through for
;                     transparency).
;
; If execve() fails inside the child (path missing, wrong
; arch, not executable), the child raw-exits with status 127
; and the parent sees `wstatus = 127 << 8` — matching the
; convention shell uses for "command not found". Callers can
; distinguish "spawned but exited with 127 by choice" from
; "failed to spawn" only by inspecting the target's known
; exit codes.
;
; Callee-saved r12/r13/r14 hold the args across the fork
; call. Stack layout across the fork/wait cycle:
;
;   [rsp + 0]  wstatus scratch (8 bytes, only 4 used)
;   [rsp + 8]  16-byte alignment padding

%include "syscall.inc"

default rel

extern fork, wait4, execve

global spawn_wait

section .text

spawn_wait:
    push r12
    push r13
    push r14
    sub rsp, 16                     ; wstatus at [rsp], 8 bytes padding
    mov r12, rdi                    ; save path
    mov r13, rsi                    ; save argv
    mov r14, rdx                    ; save envp

    call fork
    test rax, rax
    js .done                        ; -errno from fork → return as-is
    jz .child

    ; ---- Parent: rax = child pid ----
    mov rdi, rax                    ; pid
    lea rsi, [rsp]                  ; &wstatus
    xor edx, edx                    ; options = 0 (blocking)
    xor ecx, ecx                    ; rusage = NULL
    call wait4
    test rax, rax
    js .done                        ; -errno from wait4 → return as-is
    mov eax, [rsp]                  ; wstatus (32 bits is enough)

.done:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    ret

.child:
    ; ---- Child: replace image with `path` ----
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call execve
    ; execve returned — the load failed. Exit 127 (the shell
    ; convention for "command not found") so the parent's
    ; wait4 produces a distinguishable wstatus.
    mov rax, SYS_exit
    mov edi, 127
    syscall
