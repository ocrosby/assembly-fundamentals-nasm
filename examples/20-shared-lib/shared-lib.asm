; Call the C library's `puts` function to write
; `"Hello, shared library!"` to standard output. Delegates the
; whole string-write to a shared library — `libSystem` on macOS,
; `libc` on Linux. No `sys_write`, no manual length computation,
; no `equ $ - msg`; `puts` handles the loop, the length, and the
; trailing newline.
;
; New in this example: declaring an external symbol with `extern`,
; and calling a function from a shared library. The static linker
; resolves the name at link time; the dynamic linker maps the
; actual shared library into the process at run time.
;
; Cross-platform notes worth calling out:
;
;   - **macOS mangles C symbols with a leading underscore.** The
;     linker looks for `_puts`, not `puts`. NASM does no automatic
;     mangling — the source names each platform's symbol
;     explicitly via a `%define`.
;   - **Entry point is `main`/`_main`, not `_start`.** On Linux this
;     example links through `gcc`, whose `crt0` startup calls
;     `main` after initializing libc. On macOS, `ld -lSystem`
;     already resolves `_main` as the default entry.
;   - **Stack alignment.** The System V AMD64 ABI requires `rsp` to
;     be 16-byte aligned at the moment of `call`. Runtime hands us
;     an aligned `rsp`; the upcoming `call` will push an 8-byte
;     return address, leaving the callee with an 8-mod-16 `rsp`.
;     `sub rsp, 8` pre-aligns so `puts` sees the alignment it
;     expects — miss this and `puts` may crash inside SIMD code.

%ifdef MACOS
%define MAIN_SYM _main
%define PUTS_SYM _puts
%else
%define MAIN_SYM main
%define PUTS_SYM puts
%endif

extern PUTS_SYM

default rel
global MAIN_SYM

section .text

MAIN_SYM:
    sub rsp, 8                       ; pre-align for the `call`

    lea rdi, [msg]                   ; arg 1: pointer to NUL-terminated string
    call PUTS_SYM                    ; puts(msg) — prints msg + '\n'

    add rsp, 8                       ; restore

    xor eax, eax                     ; return value = 0
    ret                              ; back to runtime, which calls exit(0)

section .rodata
msg: db "Hello, shared library!", 0  ; NUL-terminated for puts
