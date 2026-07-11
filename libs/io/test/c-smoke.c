/*
 * c-smoke.c — verify libio.a is linkable and callable from C.
 *
 * Same shape as libs/sock/test/c-smoke.c: pin every extern to
 * the bare NASM symbol name via GCC __asm__ labels (Mach-O's
 * default C ABI would look for _open / _openat and never see
 * libio's open / openat), and skip <fcntl.h> so libc's inline
 * wrappers do not shadow the archive.
 *
 * Compiles a small round-trip that would fail at LINK time if
 * libio.a were absent (openat is the sentinel — libc has open()
 * everywhere but openat() has a __asm__-pinned reference here,
 * so the linker must find it in the archive).
 *
 * Compile: cc c-smoke.c ../libio.a -o c-smoke
 * Run:     ./c-smoke
 *
 * Prints "PASS\n" and exits 0 on success. Prints "FAIL:<n>\n"
 * to stderr and exits 1 on the first failing check.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Intentionally NOT including <unistd.h> or <fcntl.h>:
 *   * <unistd.h> already declares lseek/pread/pwrite with
 *     Darwin's off_t (long long) — a conflicting-types error
 *     if libio's extern declaration uses `long`.
 *   * <fcntl.h> on Darwin can turn open()/openat() into inline
 *     wrappers around __open() / __openat(), which never touch
 *     libio's symbols at all.
 *
 * Skipping both means every declaration below is authoritative,
 * with __asm__ labels choosing whether a call binds to libio
 * (bare name) or to libc (underscored name emitted by clang's
 * default Mach-O ABI). O_* / AT_FDCWD / SEEK_* are hardcoded
 * for the same reason.
 */
#define O_RDONLY 0
#define O_RDWR   2
#ifdef __APPLE__
#  define O_CREAT  0x0200
#  define AT_FDCWD (-2)
#else
#  define O_CREAT  0x40
#  define AT_FDCWD (-100)
#endif
#define SEEK_SET 0
#define SEEK_END 2

/* libio symbols — __asm__ labels pin the reference to the bare
 * name NASM emits, so the linker resolves them against libio's
 * objects rather than libc's underscored variants. */
extern int  open  (const char *path, int flags, unsigned mode)             __asm__("open");
extern int  openat(int dirfd, const char *path, int flags, unsigned mode)  __asm__("openat");
extern long lseek (int fd, long offset, int whence)                        __asm__("lseek");
extern long pread (int fd, void *buf, unsigned long count, long offset)    __asm__("pread");
extern long pwrite(int fd, const void *buf, unsigned long count, long offset) __asm__("pwrite");

/* v1.1 libio symbols. fstat's second arg is opaque here — a
 * caller-allocated 144-byte buffer covers both platforms. */
extern int  fstat (int fd, void *statbuf)                                  __asm__("fstat");
extern int  unlink(const char *path)                                       __asm__("unlink");
extern int  mkdir (const char *path, unsigned mode)                        __asm__("mkdir");
extern int  rmdir (const char *path)                                       __asm__("rmdir");
extern int  io_size(int fd, long *out)                                     __asm__("io_size");

/* v1.2: path-based stat + atomic rename. */
extern int  stat  (const char *path, void *statbuf)                        __asm__("stat");
extern int  rename(const char *oldpath, const char *newpath)               __asm__("rename");

/* close still lives in libsock, not libio. Fall through to libc's
 * default so we don't pull libsock in for one syscall. */
extern int close(int fd);

static int fail(int id) {
    fprintf(stderr, "FAIL:%d\n", id);
    return 1;
}

int main(void) {
    /* Use a deterministic path — this is a smoke, not a real
     * TempFile helper. The harness cleans up unconditionally. */
    const char *path = "/tmp/libio-c-smoke.tmp";

    int fd = open(path, O_RDWR | O_CREAT, 0600);
    if (fd < 0)                                     return fail(1);

    if (pwrite(fd, "hello", 5, 0) != 5)             return fail(2);
    if (pwrite(fd, "world", 5, 5) != 5)             return fail(3);

    if (lseek(fd, 0, SEEK_END) != 10)               return fail(4);
    if (lseek(fd, 0, SEEK_SET) != 0)                return fail(5);

    char buf[10] = {0};
    if (pread(fd, buf, 10, 0) != 10)                return fail(6);
    if (memcmp(buf, "helloworld", 10) != 0)         return fail(7);

    if (close(fd) != 0)                             return fail(8);

    /* Reopen via openat — this is the sentinel that proves
     * libio was actually linked. libc's openat would work too,
     * but the __asm__ label above pins our reference to the
     * bare symbol name, which only libio provides. */
    fd = openat(AT_FDCWD, path, O_RDONLY, 0);
    if (fd < 0)                                     return fail(9);

    memset(buf, 0, sizeof buf);
    if (pread(fd, buf, 5, 5) != 5)                  return fail(10);
    if (memcmp(buf, "world", 5) != 0)               return fail(11);

    if (close(fd) != 0)                             return fail(12);

    /* v1.1: exercise the new symbols. */

    /* 13: io_size on a fresh openat of the same file → 10. */
    fd = openat(AT_FDCWD, path, O_RDONLY, 0);
    if (fd < 0)                                     return fail(13);
    long sz = -1;
    if (io_size(fd, &sz) != 0 || sz != 10)          return fail(14);

    /* 15: fstat on the same fd — sanity-check that the wrapper
     * populates SOMETHING nonzero at the file-size offset. The
     * exact offset differs per platform; io_size (above) is the
     * canonical portable check. Here we just prove fstat runs. */
    unsigned char statbuf[144] = {0};
    if (fstat(fd, statbuf) != 0)                    return fail(15);
    if (close(fd) != 0)                             return fail(16);

    /* 17-18: mkdir + rmdir round-trip. */
    const char *dir = "/tmp/libio-c-smoke.dir";
    rmdir(dir);                                     /* best-effort clean */
    if (mkdir(dir, 0755) != 0)                      return fail(17);
    if (rmdir(dir) != 0)                            return fail(18);

    /* 19-20: unlink the tempfile, then confirm a second unlink
     * returns a negative errno. */
    if (unlink(path) != 0)                          return fail(19);
    if (unlink(path) >= 0)                          return fail(20);

    /* v1.2: stat + rename end-to-end. */
    const char *p1 = "/tmp/libio-c-smoke.tmp";
    const char *p2 = "/tmp/libio-c-smoke.tmp2";
    unlink(p1); unlink(p2);
    fd = open(p1, O_RDWR | O_CREAT, 0600);
    if (fd < 0)                                     return fail(21);
    if (pwrite(fd, "abc", 3, 0) != 3)               return fail(22);
    if (close(fd) != 0)                             return fail(23);

    /* 24: stat on the freshly-created file — succeeds. */
    if (stat(p1, statbuf) != 0)                     return fail(24);

    /* 25: rename to a fresh target. */
    if (rename(p1, p2) != 0)                        return fail(25);

    /* 26: stat on the old path now fails (source gone). */
    if (stat(p1, statbuf) >= 0)                     return fail(26);

    /* 27: stat on the new path succeeds. */
    if (stat(p2, statbuf) != 0)                     return fail(27);

    unlink(p2);

    puts("PASS");
    return 0;
}
