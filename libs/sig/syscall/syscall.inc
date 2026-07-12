; syscall.inc — shared per-platform syscall numbers, sigset
; layout, and signal / sigprocmask constants for libsig.
;
; Every wrapper in libsig includes this file. It centralizes:
;
;   * The SYS_* syscall numbers. On macOS these are BSD-class
;     syscalls with the 0x2000000 class prefix. On Linux the
;     rt_sig* variants are the ones the kernel actually
;     implements — the legacy sig* syscalls exist only for
;     32-bit compat and take a smaller sigset_t.
;
;   * SIGSET_BYTES — the number of bytes each sigset_t
;     manipulation dereferences. Linux rt_sig* syscalls take a
;     `sigsetsize` argument that must equal `_NSIG/8 = 8`;
;     macOS BSD sigprocmask reads 4 bytes (the older 32-bit
;     mask). Callers reserve at least SIGSET_BYTES for a
;     sigset buffer.
;
;   * SIG_BLOCK / SIG_UNBLOCK / SIG_SETMASK — the three `how`
;     values for sigprocmask. The numeric values differ
;     between the platforms; libsig normalizes them so callers
;     use the constants regardless of target.
;
;   * A minimal set of portable signal numbers (SIGINT, SIGTERM,
;     SIGKILL, SIGPIPE). Signals 1..15 agree across macOS and
;     Linux; libsig exposes the ones consumers actually need
;     rather than the whole POSIX list.
;
;   * SYSCALL_NORM and SYSCALL_ARG4 come from the shared
;     `syscall-common.inc` that every archive in `libs/` uses.

%ifndef LIBSIG_SYSCALL_INC
%define LIBSIG_SYSCALL_INC

%include "syscall-common.inc"

%ifdef MACOS
; BSD sigprocmask (48), sigpending (52), sigaction (46). All
; three take a pointer to a 4-byte sigset_t; kernel does not
; dereference an 8th byte.
%define SYS_sigprocmask 0x2000030   ; 48
%define SYS_sigpending  0x2000034   ; 52
%define SYS_sigaction   0x200002e   ; 46
%define SIGSET_BYTES    4

; macOS SIG_* how values (see /usr/include/sys/signal.h).
%define SIG_BLOCK       1
%define SIG_UNBLOCK     2
%define SIG_SETMASK     3

; struct __sigaction layout (Darwin xnu signal.h):
;   +0   sa_handler   (8 bytes)
;   +8   sa_tramp     (8 bytes) — userspace trampoline; only
;                                consulted when a real handler
;                                is installed. Safe to leave
;                                NULL for SIG_DFL / SIG_IGN.
;   +16  sa_mask      (4 bytes)
;   +20  sa_flags     (4 bytes)
;   total = 24 bytes
%define SIGACTION_SIZE  24
%define SA_HANDLER_OFF  0
%define SA_TRAMP_OFF    8
%define SA_MASK_OFF     16
%define SA_FLAGS_OFF    20
%else
; Linux uses the rt_sig* variants (kernel signals 1..64). The
; legacy sig* variants exist for 32-bit compat and take a
; 32-bit sigset_t which does not cover the real-time signal
; range. Every kernel since 2.6 routes the C sigprocmask
; through rt_sigprocmask, and libsig does the same.
%define SYS_sigprocmask 14          ; rt_sigprocmask
%define SYS_sigpending  127         ; rt_sigpending
%define SYS_sigaction   13          ; rt_sigaction
%define SIGSET_BYTES    8

; Linux SIG_* how values (see /usr/include/bits/sigaction.h).
%define SIG_BLOCK       0
%define SIG_UNBLOCK     1
%define SIG_SETMASK     2

; struct kernel_sigaction layout (see arch/x86/include/asm/signal.h
; in the Linux source):
;   +0   sa_handler   (8 bytes)
;   +8   sa_flags     (8 bytes)  — includes SA_RESTORER for real
;                                   handlers (v1.3+).
;   +16  sa_restorer  (8 bytes)  — SA_RESTORER trampoline. Only
;                                   consulted for real handlers.
;   +24  sa_mask      (8 bytes)
;   total = 32 bytes
%define SIGACTION_SIZE  32
%define SA_HANDLER_OFF  0
%define SA_FLAGS_OFF    8
%define SA_RESTORER_OFF 16
%define SA_MASK_OFF     24
%endif

; Handler dispositions — SIG_DFL restores the default action
; for a signal (usually terminate; SIGCHLD's default is ignore
; and stopping signals default to stop). SIG_IGN discards
; deliveries silently — the process observes the syscall
; return but no handler runs.
;
; Custom handler functions (a pointer to caller-owned code
; that returns) are NOT yet supported. Installing one requires
; a SA_RESTORER trampoline on Linux and an sa_tramp trampoline
; on macOS — both deferred to v1.3 pending a clean
; cross-platform design.
%define SIG_DFL         0
%define SIG_IGN         1

; Portable signal numbers. Values 1..15 agree between macOS
; and Linux (they descend from the original BSD numbering
; that POSIX standardized). Callers who want signals in the
; 16..31 range where the platforms diverge (SIGUSR1 = 30 on
; macOS but 10 on Linux) should split their code with
; %ifdef MACOS rather than expect libsig to normalize.
%define SIGHUP          1
%define SIGINT          2           ; Ctrl-C
%define SIGQUIT         3
%define SIGILL          4
%define SIGTRAP         5
%define SIGABRT         6
%define SIGFPE          8
%define SIGKILL         9           ; uncatchable
%define SIGSEGV         11
%define SIGPIPE         13          ; write to closed pipe / socket
%define SIGALRM         14
%define SIGTERM         15          ; polite shutdown

%endif ; LIBSIG_SYSCALL_INC
