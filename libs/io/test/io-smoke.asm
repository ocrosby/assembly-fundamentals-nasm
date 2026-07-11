; io-smoke.asm — success-path smoke test for libio's file
; syscall wrappers.
;
; Sequence:
;   1  open(TMPFILE, O_CREAT|O_RDWR, 0600)          → server_fd
;   2  pwrite(fd, "hello", 5, 0)                    → 5
;   3  pwrite(fd, "world", 5, 5)                    → 5
;   4  lseek(fd, 0, SEEK_END)                       → 10  (size check)
;   5  lseek(fd, 3, SEEK_SET)                       → 3
;   6  pread(fd, buf, 4, 3)                         → 4
;   7  verify buf[0..4] == "lowo"
;   8  close via a direct syscall (libio does not export close;
;      that lives in libsock, and pulling libsock in just to
;      close one fd would confuse the coverage story)
;   9  openat(AT_FDCWD, TMPFILE, O_RDONLY)          → fd2
;   A  pread(fd2, buf, 5, 5)                        → 5
;   B  verify buf[0..5] == "world"
;   C  close fd2 via direct syscall
;
; v1.1 additions (fd3 reopen so we can exercise fstat / io_size
; without teardown-then-setup):
;   D  openat(AT_FDCWD, TMPFILE, O_RDONLY)          → fd3
;   E  fstat(fd3, statbuf), st_size at ST_SIZE_OFF  → 10
;   F  io_size(fd3, &size_out)                      → 0, out=10
;   G  close fd3 via direct syscall
;
; v1.1 namespace ops (independent of the tempfile above):
;   H  mkdir(DIRPATH, 0755)                         → 0
;   I  rmdir(DIRPATH)                               → 0
;
; v1.2 metadata + rename (chained through TMPFILE):
;   J  stat(TMPFILE, statbuf), st_size at
;      ST_SIZE_OFF                                  → 10
;   K  rename(TMPFILE, RENAMED_PATH)                → 0
;   L  stat(TMPFILE, statbuf)  (source gone)        → < 0
;   M  stat(RENAMED_PATH, statbuf), st_size         → 10
;   N  unlink(RENAMED_PATH)                         → 0
;   O  unlink(RENAMED_PATH) (already gone)          → < 0
;
; TMPFILE is a path the harness generates via mktemp and injects
; via `-DTMPFILE="..."`; run.sh removes it after the test.
;
; Prints "PASS\n" and exits 0 when every sub-check passes.
; Prints "FAIL:<id>\n" to stderr and exits 1 on the first
; failure, using the sub-check id from the sequence above.

%ifndef TMPFILE
%define TMPFILE "/tmp/libio-smoke-default"
%endif
%ifndef DIRPATH
%define DIRPATH "/tmp/libio-smoke-dir-default"
%endif
%ifndef RENAMED_PATH
%define RENAMED_PATH "/tmp/libio-smoke-renamed-default"
%endif

; Pull in libio's syscall.inc for STATBUF_SIZE and ST_SIZE_OFF —
; the smoke test needs the platform-appropriate offset to
; verify what fstat wrote. Callers of libio in the wild do NOT
; need this: they can just use util/io-size for size lookups,
; or add named offsets to syscall.inc for other fields.
%include "syscall.inc"

; O_* flag values (POSIX). macOS and Linux happen to agree on
; O_RDONLY / O_WRONLY / O_RDWR / O_CREAT / O_TRUNC. O_APPEND
; agrees too. The higher-value flags (O_NONBLOCK, O_SYNC, …)
; differ between platforms, but we don't use those.
%define O_RDONLY 0
%define O_RDWR   2
%define O_CREAT  0x40           ; Linux value
%ifdef MACOS
%undef  O_CREAT
%define O_CREAT  0x200          ; Darwin value
%endif

%define SEEK_SET 0
%define SEEK_END 2

; AT_FDCWD is the "resolve relative to cwd" sentinel for the
; *at() family. Both platforms encode it as a negative int, but
; they use different values.
%ifdef MACOS
%define AT_FDCWD -2
%else
%define AT_FDCWD -100
%endif

%ifdef MACOS
%define SYS_write 0x2000004
%define SYS_exit  0x2000001
%define SYS_close 0x2000006
%else
%define SYS_write 1
%define SYS_exit  60
%define SYS_close 3
%endif

default rel

extern open, openat, lseek, pread, pwrite
extern fstat, unlink, mkdir, rmdir
extern stat, rename
extern io_size

global _start
global _main

section .rodata
tmpfile:      db TMPFILE, 0
dirpath:      db DIRPATH, 0
renamed_path: db RENAMED_PATH, 0
hello:        db "hello"
world:        db "world"
exp_low:      db "lowo"

pass_msg: db "PASS", 10
pass_len: equ $ - pass_msg

; The FAIL line lives in .data because we overwrite the id
; placeholder at runtime; .rodata is strictly read-only on
; Mach-O and writing to it there raises SIGBUS.
section .data
fail_msg: db "FAIL:?", 10
fail_id   equ fail_msg + 5
fail_len  equ $ - fail_msg

section .bss
buf:      resb 32
statbuf:  resb STATBUF_SIZE                ; 144 on both platforms
size_out: resq 1                            ; scratch for io_size

section .text

_start:
_main:
    ; ---- 1: open the tempfile ----
    mov byte [fail_id], '1'
    lea rdi, [tmpfile]
    mov esi, O_RDWR | O_CREAT
    mov edx, 0600q                   ; -rw-------
    call open
    test rax, rax
    js .fail
    mov rbx, rax                     ; fd

    ; ---- 2: pwrite("hello", 5, 0) ----
    mov byte [fail_id], '2'
    mov rdi, rbx
    lea rsi, [hello]
    mov edx, 5
    xor ecx, ecx                     ; offset = 0
    call pwrite
    cmp rax, 5
    jne .fail

    ; ---- 3: pwrite("world", 5, 5) ----
    mov byte [fail_id], '3'
    mov rdi, rbx
    lea rsi, [world]
    mov edx, 5
    mov ecx, 5                       ; offset = 5
    call pwrite
    cmp rax, 5
    jne .fail

    ; ---- 4: lseek(fd, 0, SEEK_END) == 10 (post-write file size) ----
    mov byte [fail_id], '4'
    mov rdi, rbx
    xor esi, esi
    mov edx, SEEK_END
    call lseek
    cmp rax, 10
    jne .fail

    ; ---- 5: lseek(fd, 3, SEEK_SET) == 3 ----
    mov byte [fail_id], '5'
    mov rdi, rbx
    mov esi, 3
    mov edx, SEEK_SET
    call lseek
    cmp rax, 3
    jne .fail

    ; ---- 6: pread(fd, buf, 4, 3) == 4 ----
    mov byte [fail_id], '6'
    mov rdi, rbx
    lea rsi, [buf]
    mov edx, 4
    mov ecx, 3                       ; offset = 3
    call pread
    cmp rax, 4
    jne .fail

    ; ---- 7: verify buf[0..4] == "lowo" ----
    ; ("hello" + "world" = "helloworld"; offset 3 length 4 = "lowo")
    mov byte [fail_id], '7'
    mov eax, [rel exp_low]           ; expected 4 bytes
    cmp eax, dword [buf]
    jne .fail

    ; ---- 8: close(fd) via raw syscall ----
    mov byte [fail_id], '8'
    mov rdi, rbx
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close1_ok
    neg rax
.close1_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- 9: reopen via openat(AT_FDCWD, TMPFILE, O_RDONLY) ----
    mov byte [fail_id], '9'
    mov edi, AT_FDCWD
    lea rsi, [tmpfile]
    mov edx, O_RDONLY
    xor ecx, ecx                     ; mode ignored without O_CREAT
    call openat
    test rax, rax
    js .fail
    mov rbx, rax                     ; fd2

    ; ---- A: pread(fd2, buf, 5, 5) == 5 ----
    mov byte [fail_id], 'A'
    mov rdi, rbx
    lea rsi, [buf]
    mov edx, 5
    mov ecx, 5
    call pread
    cmp rax, 5
    jne .fail

    ; ---- B: verify buf[0..5] == "world" ----
    mov byte [fail_id], 'B'
    mov eax, [rel world]             ; first 4 bytes
    cmp eax, dword [buf]
    jne .fail
    mov al, [rel world + 4]          ; 5th byte
    cmp al, [buf + 4]
    jne .fail

    ; ---- C: close(fd2) ----
    mov byte [fail_id], 'C'
    mov rdi, rbx
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close2_ok
    neg rax
.close2_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- D: reopen for fstat / io_size (fd3) ----
    mov byte [fail_id], 'D'
    mov edi, AT_FDCWD
    lea rsi, [tmpfile]
    mov edx, O_RDONLY
    xor ecx, ecx
    call openat
    test rax, rax
    js .fail
    mov rbx, rax                     ; fd3

    ; ---- E: fstat(fd3, statbuf), st_size at ST_SIZE_OFF == 10 ----
    mov byte [fail_id], 'E'
    mov rdi, rbx
    lea rsi, [statbuf]
    call fstat
    test rax, rax
    jnz .fail
    mov rax, [statbuf + ST_SIZE_OFF]
    cmp rax, 10
    jne .fail

    ; ---- F: io_size(fd3, &size_out); size_out == 10 ----
    mov byte [fail_id], 'F'
    mov rdi, rbx
    lea rsi, [size_out]
    call io_size
    test rax, rax
    jnz .fail
    mov rax, [size_out]
    cmp rax, 10
    jne .fail

    ; ---- G: close(fd3) ----
    mov byte [fail_id], 'G'
    mov rdi, rbx
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close3_ok
    neg rax
.close3_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- H: mkdir(DIRPATH, 0755) → 0 ----
    mov byte [fail_id], 'H'
    lea rdi, [dirpath]
    mov esi, 0755q                   ; rwx-r-x-r-x
    call mkdir
    test rax, rax
    jnz .fail

    ; ---- I: rmdir(DIRPATH) → 0 ----
    mov byte [fail_id], 'I'
    lea rdi, [dirpath]
    call rmdir
    test rax, rax
    jnz .fail

    ; ---- J: stat(TMPFILE, statbuf) → 0, st_size == 10 ----
    mov byte [fail_id], 'J'
    lea rdi, [tmpfile]
    lea rsi, [statbuf]
    call stat
    test rax, rax
    jnz .fail
    mov rax, [statbuf + ST_SIZE_OFF]
    cmp rax, 10
    jne .fail

    ; ---- K: rename(TMPFILE, RENAMED_PATH) → 0 ----
    mov byte [fail_id], 'K'
    lea rdi, [tmpfile]
    lea rsi, [renamed_path]
    call rename
    test rax, rax
    jnz .fail

    ; ---- L: stat(TMPFILE, statbuf) → < 0 (source gone) ----
    mov byte [fail_id], 'L'
    lea rdi, [tmpfile]
    lea rsi, [statbuf]
    call stat
    test rax, rax
    jns .fail

    ; ---- M: stat(RENAMED_PATH, statbuf) → 0, st_size == 10 ----
    mov byte [fail_id], 'M'
    lea rdi, [renamed_path]
    lea rsi, [statbuf]
    call stat
    test rax, rax
    jnz .fail
    mov rax, [statbuf + ST_SIZE_OFF]
    cmp rax, 10
    jne .fail

    ; ---- N: unlink(RENAMED_PATH) → 0 ----
    mov byte [fail_id], 'N'
    lea rdi, [renamed_path]
    call unlink
    test rax, rax
    jnz .fail

    ; ---- O: unlink(RENAMED_PATH) again → < 0 (already gone) ----
    mov byte [fail_id], 'O'
    lea rdi, [renamed_path]
    call unlink
    test rax, rax
    jns .fail

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
