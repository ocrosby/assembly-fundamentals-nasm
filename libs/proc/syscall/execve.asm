; execve(path, argv, envp) -> rax = -errno (never returns on success)
;
; Replace the calling process's memory image with the program
; loaded from `path`. On success, control transfers to the new
; program's entry point — there is no "return from execve" for
; the caller to observe. On failure, execve returns with a
; negative errno in rax and the caller's memory is untouched.
;
; Arguments:
;   rdi = path*  NUL-terminated absolute or relative path to
;                the target binary. If the file is a shell
;                script starting with `#!`, the kernel invokes
;                the interpreter named on that line.
;   rsi = argv*  pointer to a NULL-terminated array of
;                `char*`. argv[0] is convention: the program's
;                own name (typically the same as `path` or its
;                basename). If argv[0] is NULL, execve fails
;                with -EFAULT on Linux and -EINVAL on macOS.
;   rdx = envp*  pointer to a NULL-terminated array of
;                `char*` of the form "KEY=VALUE". Pass a
;                pointer to a single NULL entry for an empty
;                environment; some kernels reject an outright
;                NULL envp pointer.
;
; Return (only when the call fails):
;   -ENOENT      path does not exist
;   -EACCES      path is not executable, or a directory
;                component of path is not searchable
;   -ENOEXEC     path exists and is executable but is neither
;                a valid binary format nor a #! interpreter
;                script
;   -E2BIG       argv + envp exceed the kernel's ARG_MAX
;
; State that survives an execve:
;   * pid, ppid, session id, process group id
;   * open file descriptors, unless FD_CLOEXEC was set (via
;     fcntl F_SETFD) before the call
;   * signal-mask and pending-signal state
;   * controlling terminal, working directory, umask, real /
;     effective uid & gid (subject to setuid/setgid bits on
;     the target)
;   * resource limits (setrlimit)
;
; State that is reset:
;   * signal *handlers* — inherited handlers are replaced with
;     SIG_DFL (unless the disposition was SIG_IGN, which
;     survives)
;   * shared memory attachments, timers, async I/O

%include "syscall.inc"

default rel

global execve

section .text

execve:
    mov rax, SYS_execve
    SYSCALL_NORM
    ret
