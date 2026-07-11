; syscall.inc — shared per-platform syscall numbers and macros
;
; Every wrapper in libio includes this file. It centralizes:
;
;   * The SYS_* syscall numbers, resolved differently per platform.
;     macOS BSD-class syscalls carry the 0x2000000 class prefix
;     (drawn from <sys/syscall.h> in the Xcode command-line SDK).
;     Linux uses the plain x86-64 syscall numbers from
;     <asm/unistd_64.h>.
;
;   * SYSCALL_NORM — normalizes the macOS carry-flag error
;     convention to Linux's "negative errno in rax" convention, so
;     every wrapper returns non-negative on success and a negative
;     errno on failure regardless of platform. On Linux the macro
;     is just `syscall` because the kernel already writes -errno
;     into rax.
;
;   * SYSCALL_ARG4 — the System V AMD64 ABI passes the 4th
;     argument in rcx, but the kernel's syscall ABI clobbers rcx
;     (it holds the return address) and expects the 4th arg in
;     r10. Wrappers with four or more arguments must translate
;     rcx→r10 before invoking the syscall.
;
; libio and libsock ship duplicate copies of these macros so each
; archive stays self-contained. If a third archive lands with the
; same pattern the shared definitions should promote to a
; libs/-level include.

%ifndef LIBIO_SYSCALL_INC
%define LIBIO_SYSCALL_INC

%ifdef MACOS
%define SYS_open   0x2000005
%define SYS_pread  0x2000099
%define SYS_pwrite 0x200009a
%define SYS_lseek  0x20000c7
%define SYS_openat 0x20001cf
; v1.1: metadata + namespace ops.
; SYS_fstat / SYS_stat here are Darwin's 64-bit-inode
; variants (fstat64 = BSD syscall 339, stat64 = 338). The
; older SYS_fstat (189) / SYS_stat (188) return a struct
; with 32-bit inode numbers that macOS deprecated once wide
; inodes shipped; libio wraps the wider pair so callers see
; identical field offsets across the two symbols.
%define SYS_unlink 0x200000a
%define SYS_mkdir  0x2000088
%define SYS_rmdir  0x2000089
%define SYS_fstat  0x2000153
; v1.2 additions.
%define SYS_stat   0x2000152
%define SYS_rename 0x2000080
; v1.3 additions.
; SYS_lstat is Darwin's 64-bit-inode lstat64 (BSD 340), matching
; the fstat64 (339) and stat64 (338) numbers used by v1.1 / v1.2.
%define SYS_lstat     0x2000154
%define SYS_chmod     0x200000f
%define SYS_chown     0x2000010
%define SYS_symlink   0x2000039
%define SYS_readlink  0x200003a
%define SYS_truncate  0x20000c8
%define SYS_ftruncate 0x20000c9
; v1.4: directory iteration. getdirentries64 (BSD 344) uses the
; 64-bit-inode `struct dirent` layout that pairs with our stat64
; wrapper — same wide inode field on both syscalls.
%define SYS_getdents  0x2000158
%else
%define SYS_open   2
%define SYS_lseek  8
%define SYS_pread  17
%define SYS_pwrite 18
%define SYS_openat 257
; v1.1 additions on Linux. SYS_fstat / SYS_stat = 5 / 4 already
; return the 64-bit stat struct on x86_64, so no fstat64/stat64
; syscall exists.
%define SYS_unlink 87
%define SYS_mkdir  83
%define SYS_rmdir  84
%define SYS_fstat  5
; v1.2 additions.
%define SYS_stat   4
%define SYS_rename 82
; v1.3 additions.
%define SYS_lstat     6
%define SYS_chmod     90
%define SYS_chown     92
%define SYS_symlink   88
%define SYS_readlink  89
%define SYS_truncate  76
%define SYS_ftruncate 77
; v1.4: directory iteration.
%define SYS_getdents  217
%endif

; The stat struct is 144 bytes on both macOS (`struct stat64`)
; and Linux (`struct stat` on x86_64), but the field offsets
; differ. Wrappers keep the buffer opaque; util/io-size.asm
; uses ST_SIZE_OFF internally to pull the file size out
; portably. Callers that want other fields should add a
; matching offset here rather than hardcoding it at the call
; site.
%define STATBUF_SIZE 144
%ifdef MACOS
; struct stat64: st_dev(4) st_mode(2) st_nlink(2) st_ino(8)
; st_uid(4) st_gid(4) st_rdev(4) pad(4) atime(16) mtime(16)
; ctime(16) birthtime(16) → st_size at +96.
%define ST_SIZE_OFF  96
%else
; struct stat: st_dev(8) st_ino(8) st_nlink(8) st_mode(4)
; st_uid(4) st_gid(4) pad(4) st_rdev(8) → st_size at +48.
%define ST_SIZE_OFF  48
%endif

; -----------------------------------------------------------------
; v1.4: dirent record layout for getdents-returned buffers.
;
; The kernel returns a stream of variable-length records. Both
; platforms share the same u16 d_reclen at offset 16, and the
; d_type byte + NUL-terminated d_name follow, but at different
; offsets:
;
;   Linux linux_dirent64:
;     +0  u64 d_ino
;     +8  i64 d_off
;     +16 u16 d_reclen
;     +18 u8  d_type
;     +19 char d_name[] (NUL-terminated, record-padded)
;
;   macOS struct dirent (64-bit-inode):
;     +0  u64 d_ino
;     +8  u64 d_seekoff
;     +16 u16 d_reclen
;     +18 u16 d_namlen
;     +20 u8  d_type
;     +21 char d_name[] (NUL-terminated, record-padded)
;
; util/dir-iter.asm walks these portably by reading d_reclen at
; the shared offset and consulting D_TYPE_OFF / D_NAME_OFF for
; the fields that differ.

%define D_RECLEN_OFF  16
%ifdef MACOS
%define D_TYPE_OFF    20
%define D_NAME_OFF    21
%else
%define D_TYPE_OFF    18
%define D_NAME_OFF    19
%endif

; File-type constants for d_type. Both platforms use identical
; values (drawn from BSD's <dirent.h> which POSIX later
; standardized). DT_UNKNOWN is the sentinel filesystems return
; when they cannot cheaply report the type — the caller must
; fall back to stat/lstat to disambiguate.
%define DT_UNKNOWN 0
%define DT_FIFO    1
%define DT_CHR     2
%define DT_DIR     4
%define DT_BLK     6
%define DT_REG     8
%define DT_LNK     10
%define DT_SOCK    12

; -----------------------------------------------------------------
; v1.4: dir_iter caller-allocated iterator state.
;
;   [+0..7]     fd (u64; only low 32 used, upper zero)
;   [+8..15]    position (in-out for macOS getdirentries64;
;               ignored on Linux)
;   [+16..23]   read_bytes (bytes returned by the most recent
;               getdents refill)
;   [+24..31]   cursor (bytes already consumed from the buffer)
;   [+32..4127] buf (4096-byte scratch for the raw dirent
;               records)
;
; Total 4128 bytes. Callers reserve `resb DIR_ITER_SIZE` in .bss
; or `sub rsp, DIR_ITER_SIZE` on the stack; the iterator has no
; heap dependency and its whole state travels in the caller's
; frame.
%define DIR_ITER_FD           0
%define DIR_ITER_POSITION     8
%define DIR_ITER_READ_BYTES   16
%define DIR_ITER_CURSOR       24
%define DIR_ITER_BUF          32
%define DIR_ITER_BUF_SIZE     4096
%define DIR_ITER_SIZE         4128

%macro SYSCALL_NORM 0
    syscall
%ifdef MACOS
    jnc %%ok                        ; CF=0 → success
    neg rax                         ; CF=1 → positive errno → -errno
%%ok:
%endif
%endmacro

%macro SYSCALL_ARG4 0
    mov r10, rcx                    ; 4th arg: SysV rcx → syscall r10
%endmacro

%endif ; LIBIO_SYSCALL_INC
