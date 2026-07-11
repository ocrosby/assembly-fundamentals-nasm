; fork(void) -> rax = child pid (parent), 0 (child), or -errno
;
; Duplicates the calling process. After a successful call the
; kernel schedules two nearly-identical processes; each returns
; from the same syscall site:
;
;   * In the parent, rax = the child's pid (a positive integer).
;   * In the child,  rax = 0.
;   * On failure (no child was created), rax = -errno in the
;     original process.
;
; The parent and child differ in:
;
;   * pid (child's is fresh)
;   * ppid (child's parent is the caller)
;   * pending signals (child inherits an empty set)
;   * resource-usage counters (child's are zeroed)
;   * file locks (fcntl F_SETLK locks belong to the parent)
;
; Everything else — open fds, memory contents, signal handlers,
; working directory, umask, controlling terminal — is copied
; verbatim (copy-on-write for memory). fd close-on-exec state
; determines what survives across a subsequent execve.
;
; On macOS, fork() is deprecated in favor of posix_spawn() for
; new code, but the raw syscall (SYS_fork = 2) still works and
; that is what libproc exposes. Callers writing new
; process-launch machinery from raw assembly and wanting the
; posix_spawn ergonomics will have to wait for a future
; libproc release (or write it themselves — posix_spawn is
; itself an XNU syscall, not a libc-side construction).

%include "syscall.inc"

default rel

global fork

section .text

fork:
%ifdef MACOS
    ; XNU's fork returns:
    ;   parent: rax = child pid
    ;   child:  rax = child pid, rdx = 1  (that's the sentinel)
    ; libc's fork rewrites the child's rax to 0 based on rdx=1.
    ; We replicate that here so callers see the POSIX
    ; convention.
    mov rax, SYS_fork
    syscall
    jnc .no_error
    neg rax                         ; -errno
    ret
.no_error:
    test edx, edx
    jz .parent                      ; edx=0 → parent
    xor eax, eax                    ; edx=1 → child; return 0
.parent:
    ret
%else
    mov rax, SYS_fork
    SYSCALL_NORM
    ret
%endif
