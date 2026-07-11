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
; v1.3 truncation, permission, symlink chain (chained through
; TMPFILE_V13 → SYMLINK_PATH; both cleaned up at the end):
;   P  open(TMPFILE_V13, O_RDWR|O_CREAT|O_TRUNC,
;          0644)                                    → fd
;   Q  pwrite(fd, "abcdefghij", 10, 0)              → 10
;   R  ftruncate(fd, 5)                             → 0
;   S  io_size(fd, &size_out); size_out            == 5
;   T  close(fd)
;   U  truncate(TMPFILE_V13, 3)                     → 0
;   V  stat(TMPFILE_V13, statbuf); st_size         == 3
;   W  chmod(TMPFILE_V13, 0644)                     → 0
;   X  chown(TMPFILE_V13, -1, -1) (leave-as-is)     → 0
;   Y  symlink(TMPFILE_V13, SYMLINK_PATH)           → 0
;   Z  readlink(SYMLINK_PATH, linkbuf, 128)         → > 0
;   a  lstat(SYMLINK_PATH, statbuf)                 → 0
;   b  unlink(SYMLINK_PATH)                         → 0
;   c  unlink(TMPFILE_V13)                          → 0
;
; v1.4 directory iteration (ITER_DIR is a fresh mktemp'd dir
; pre-populated by run.sh with three regular files):
;   d  dir_iter_open(iter, ITER_DIR)                → 0
;   e  loop dir_iter_next until 0; count           == 5
;      (".", "..", "a", "b", "c" — exact contents
;       written into the fixture by run.sh)
;   f  dir_iter_close(iter)                         → 0
;
; v1.5 *at() family (AT_DIR is a fresh mktemp'd dir created
; by run.sh; all subsequent ops are scoped through its dirfd):
;   g  open(AT_DIR, O_RDONLY, 0)                    → dirfd
;   h  mkdirat(dirfd, "sub", 0755)                  → 0
;   i  unlinkat(dirfd, "sub", AT_REMOVEDIR)         → 0
;   j  openat(dirfd, "f", O_CREAT|O_RDWR, 0644)     → close
;   k  renameat(dirfd, "f", dirfd, "g")             → 0
;   l  fstatat(dirfd, "g", statbuf, 0)              → 0
;   m  symlinkat("g", dirfd, "ln")                  → 0
;   n  readlinkat(dirfd, "ln", linkbuf, 128)        → > 0
;   o  linkat(dirfd, "g", dirfd, "h", 0)            → 0
;   p  unlinkat(dirfd, "g", 0)                      → 0
;   q  unlinkat(dirfd, "ln", 0)                     → 0
;   r  unlinkat(dirfd, "h", 0)                      → 0
;   s  close(dirfd)                                 → 0
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
%ifndef TMPFILE_V13
%define TMPFILE_V13 "/tmp/libio-smoke-v13-default"
%endif
%ifndef SYMLINK_PATH
%define SYMLINK_PATH "/tmp/libio-smoke-symlink-default"
%endif
%ifndef ITER_DIR
%define ITER_DIR "/tmp/libio-smoke-iter-default"
%endif
%ifndef AT_DIR
%define AT_DIR "/tmp/libio-smoke-at-default"
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
%define O_TRUNC  0x200          ; Linux value
%ifdef MACOS
%undef  O_CREAT
%undef  O_TRUNC
%define O_CREAT  0x200          ; Darwin value
%define O_TRUNC  0x400          ; Darwin value
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
extern lstat, chmod, chown, symlink, readlink, truncate, ftruncate
extern unlinkat, mkdirat, renameat, fstatat, symlinkat, linkat, readlinkat
extern io_size
extern dir_iter_open, dir_iter_next, dir_iter_close

global _start
global _main

section .rodata
tmpfile:      db TMPFILE, 0
dirpath:      db DIRPATH, 0
renamed_path: db RENAMED_PATH, 0
tmpfile_v13:  db TMPFILE_V13, 0
symlink_path: db SYMLINK_PATH, 0
iter_dir:     db ITER_DIR, 0
at_dir:       db AT_DIR, 0

; short relative names for the *at() family; all resolved
; against the dirfd r15 holds during v1.5 sub-checks.
at_sub:       db "sub", 0
at_f:         db "f", 0
at_g:         db "g", 0
at_h:         db "h", 0
at_ln:        db "ln", 0

hello:        db "hello"
world:        db "world"
tenbytes:     db "abcdefghij"
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
linkbuf:  resb 128                          ; scratch for readlink
iter:     resb DIR_ITER_SIZE                ; opaque dir_iter state
name_buf: resb 256                          ; scratch for dir_iter_next
type_out: resb 1                            ; DT_* out slot

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

    ; ---- P: open(TMPFILE_V13, O_RDWR|O_CREAT|O_TRUNC, 0644) ----
    mov byte [fail_id], 'P'
    lea rdi, [tmpfile_v13]
    mov esi, O_RDWR | O_CREAT | O_TRUNC
    mov edx, 0644q
    call open
    test rax, rax
    js .fail
    mov rbx, rax                     ; fd

    ; ---- Q: pwrite(fd, "abcdefghij", 10, 0) → 10 ----
    mov byte [fail_id], 'Q'
    mov rdi, rbx
    lea rsi, [tenbytes]
    mov edx, 10
    xor ecx, ecx
    call pwrite
    cmp rax, 10
    jne .fail

    ; ---- R: ftruncate(fd, 5) → 0 ----
    mov byte [fail_id], 'R'
    mov rdi, rbx
    mov esi, 5
    call ftruncate
    test rax, rax
    jnz .fail

    ; ---- S: io_size(fd, &size_out); size_out == 5 ----
    mov byte [fail_id], 'S'
    mov rdi, rbx
    lea rsi, [size_out]
    call io_size
    test rax, rax
    jnz .fail
    mov rax, [size_out]
    cmp rax, 5
    jne .fail

    ; ---- T: close(fd) via raw syscall ----
    mov byte [fail_id], 'T'
    mov rdi, rbx
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_v13_ok
    neg rax
.close_v13_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- U: truncate(TMPFILE_V13, 3) → 0 ----
    mov byte [fail_id], 'U'
    lea rdi, [tmpfile_v13]
    mov esi, 3
    call truncate
    test rax, rax
    jnz .fail

    ; ---- V: stat(TMPFILE_V13, statbuf); st_size == 3 ----
    mov byte [fail_id], 'V'
    lea rdi, [tmpfile_v13]
    lea rsi, [statbuf]
    call stat
    test rax, rax
    jnz .fail
    mov rax, [statbuf + ST_SIZE_OFF]
    cmp rax, 3
    jne .fail

    ; ---- W: chmod(TMPFILE_V13, 0644) → 0 ----
    mov byte [fail_id], 'W'
    lea rdi, [tmpfile_v13]
    mov esi, 0644q
    call chmod
    test rax, rax
    jnz .fail

    ; ---- X: chown(TMPFILE_V13, -1, -1) → 0 (no-op) ----
    ; -1 for uid/gid means "keep as-is"; safe for a non-root
    ; smoke test.
    mov byte [fail_id], 'X'
    lea rdi, [tmpfile_v13]
    mov esi, -1
    mov edx, -1
    call chown
    test rax, rax
    jnz .fail

    ; ---- Y: symlink(TMPFILE_V13, SYMLINK_PATH) → 0 ----
    mov byte [fail_id], 'Y'
    lea rdi, [tmpfile_v13]
    lea rsi, [symlink_path]
    call symlink
    test rax, rax
    jnz .fail

    ; ---- Z: readlink(SYMLINK_PATH, linkbuf, 128) > 0 ----
    mov byte [fail_id], 'Z'
    lea rdi, [symlink_path]
    lea rsi, [linkbuf]
    mov edx, 128
    call readlink
    test rax, rax
    jle .fail                        ; want strictly positive

    ; ---- a: lstat(SYMLINK_PATH, statbuf) → 0 ----
    ; Prove the wrapper runs without following the symlink;
    ; content of statbuf is not asserted (mode-field offset
    ; differs by platform and is not exposed by syscall.inc).
    mov byte [fail_id], 'a'
    lea rdi, [symlink_path]
    lea rsi, [statbuf]
    call lstat
    test rax, rax
    jnz .fail

    ; ---- b: unlink(SYMLINK_PATH) → 0 (link cleanup) ----
    mov byte [fail_id], 'b'
    lea rdi, [symlink_path]
    call unlink
    test rax, rax
    jnz .fail

    ; ---- c: unlink(TMPFILE_V13) → 0 (target cleanup) ----
    mov byte [fail_id], 'c'
    lea rdi, [tmpfile_v13]
    call unlink
    test rax, rax
    jnz .fail

    ; ---- d: dir_iter_open(iter, ITER_DIR) → 0 ----
    mov byte [fail_id], 'd'
    lea rdi, [iter]
    lea rsi, [iter_dir]
    call dir_iter_open
    test rax, rax
    jnz .fail

    ; ---- e: loop dir_iter_next until 0; count == 5 ----
    ; The harness populates ITER_DIR with three regular files
    ; (a, b, c), so iteration returns ".", "..", "a", "b", "c"
    ; — exactly five entries. rbx is a caller-saved scratch
    ; here because dir_iter_next never modifies it via ABI.
    mov byte [fail_id], 'e'
    xor ebx, ebx                     ; count = 0
.iter_loop:
    lea rdi, [iter]
    lea rsi, [name_buf]
    mov edx, 256
    lea rcx, [type_out]
    call dir_iter_next
    test rax, rax
    jz .iter_done                    ; 0 = end of directory
    js .fail                         ; -errno
    inc ebx                          ; had entry
    jmp .iter_loop
.iter_done:
    cmp ebx, 5
    jne .fail

    ; ---- f: dir_iter_close(iter) → 0 ----
    mov byte [fail_id], 'f'
    lea rdi, [iter]
    call dir_iter_close
    test rax, rax
    jnz .fail

    ; ---- g: open(AT_DIR, O_RDONLY, 0) → dirfd ----
    ; r15 holds dirfd across every v1.5 sub-check.
    mov byte [fail_id], 'g'
    lea rdi, [at_dir]
    mov esi, O_RDONLY
    xor edx, edx
    call open
    test rax, rax
    js .fail
    mov r15, rax                     ; dirfd

    ; ---- h: mkdirat(dirfd, "sub", 0755) → 0 ----
    mov byte [fail_id], 'h'
    mov rdi, r15
    lea rsi, [at_sub]
    mov edx, 0755q
    call mkdirat
    test rax, rax
    jnz .fail

    ; ---- i: unlinkat(dirfd, "sub", AT_REMOVEDIR) → 0 ----
    mov byte [fail_id], 'i'
    mov rdi, r15
    lea rsi, [at_sub]
    mov edx, AT_REMOVEDIR
    call unlinkat
    test rax, rax
    jnz .fail

    ; ---- j: openat(dirfd, "f", O_CREAT|O_RDWR, 0644) → close ----
    mov byte [fail_id], 'j'
    mov rdi, r15
    lea rsi, [at_f]
    mov edx, O_CREAT | O_RDWR
    mov ecx, 0644q
    call openat
    test rax, rax
    js .fail
    ; close the fd immediately — we only needed it to create "f".
    mov rdi, rax
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_at_f_ok
    neg rax
.close_at_f_ok:
%endif
    test rax, rax
    jnz .fail

    ; ---- k: renameat(dirfd, "f", dirfd, "g") → 0 ----
    mov byte [fail_id], 'k'
    mov rdi, r15
    lea rsi, [at_f]
    mov rdx, r15
    lea rcx, [at_g]
    call renameat
    test rax, rax
    jnz .fail

    ; ---- l: fstatat(dirfd, "g", statbuf, 0) → 0 ----
    mov byte [fail_id], 'l'
    mov rdi, r15
    lea rsi, [at_g]
    lea rdx, [statbuf]
    xor ecx, ecx
    call fstatat
    test rax, rax
    jnz .fail

    ; ---- m: symlinkat("g", dirfd, "ln") → 0 ----
    mov byte [fail_id], 'm'
    lea rdi, [at_g]
    mov rsi, r15
    lea rdx, [at_ln]
    call symlinkat
    test rax, rax
    jnz .fail

    ; ---- n: readlinkat(dirfd, "ln", linkbuf, 128) > 0 ----
    mov byte [fail_id], 'n'
    mov rdi, r15
    lea rsi, [at_ln]
    lea rdx, [linkbuf]
    mov ecx, 128
    call readlinkat
    test rax, rax
    jle .fail

    ; ---- o: linkat(dirfd, "g", dirfd, "h", 0) → 0 ----
    mov byte [fail_id], 'o'
    mov rdi, r15
    lea rsi, [at_g]
    mov rdx, r15
    lea rcx, [at_h]
    xor r8d, r8d
    call linkat
    test rax, rax
    jnz .fail

    ; ---- p: unlinkat(dirfd, "g", 0) → 0 ----
    mov byte [fail_id], 'p'
    mov rdi, r15
    lea rsi, [at_g]
    xor edx, edx
    call unlinkat
    test rax, rax
    jnz .fail

    ; ---- q: unlinkat(dirfd, "ln", 0) → 0 ----
    mov byte [fail_id], 'q'
    mov rdi, r15
    lea rsi, [at_ln]
    xor edx, edx
    call unlinkat
    test rax, rax
    jnz .fail

    ; ---- r: unlinkat(dirfd, "h", 0) → 0 ----
    mov byte [fail_id], 'r'
    mov rdi, r15
    lea rsi, [at_h]
    xor edx, edx
    call unlinkat
    test rax, rax
    jnz .fail

    ; ---- s: close(dirfd) via raw syscall ----
    mov byte [fail_id], 's'
    mov rdi, r15
    mov rax, SYS_close
    syscall
%ifdef MACOS
    jnc .close_at_dir_ok
    neg rax
.close_at_dir_ok:
%endif
    test rax, rax
    jnz .fail

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
