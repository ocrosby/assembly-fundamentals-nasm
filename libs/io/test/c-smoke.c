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

/* v1.3: permission, symlink, truncation. chown -1 (all-ones u32)
 * is "keep existing" — safe for a non-root smoke test. */
extern int  lstat    (const char *path, void *statbuf)                     __asm__("lstat");
extern int  chmod    (const char *path, unsigned mode)                     __asm__("chmod");
extern int  chown    (const char *path, unsigned uid, unsigned gid)        __asm__("chown");
extern int  symlink  (const char *target, const char *linkpath)            __asm__("symlink");
extern long readlink (const char *path, void *buf, unsigned long bufsize)  __asm__("readlink");
extern int  truncate (const char *path, long length)                       __asm__("truncate");
extern int  ftruncate(int fd, long length)                                 __asm__("ftruncate");

/* v1.4: portable directory iterator. `iter` is a caller-
 * allocated 4128-byte opaque state block. */
extern long dir_iter_open (void *iter, const char *path)                   __asm__("dir_iter_open");
extern long dir_iter_next (void *iter, char *name_buf,
                            unsigned long size, unsigned char *type_out)   __asm__("dir_iter_next");
extern long dir_iter_close(void *iter)                                     __asm__("dir_iter_close");

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

    /* v1.3: chain a fresh file through truncate/chmod/chown/
     * symlink/readlink/lstat/ftruncate. */
    fd = open(p2, O_RDWR, 0);
    if (fd < 0)                                     return fail(28);
    if (pwrite(fd, "abcdefghij", 10, 0) != 10)      return fail(29);
    if (ftruncate(fd, 5) != 0)                      return fail(30);
    long ftsz;
    if (io_size(fd, &ftsz) != 0 || ftsz != 5)       return fail(31);
    if (close(fd) != 0)                             return fail(32);

    if (truncate(p2, 3) != 0)                       return fail(33);
    if (io_size((fd = open(p2, O_RDONLY, 0)), &ftsz) != 0
        || ftsz != 3)                               return fail(34);
    if (close(fd) != 0)                             return fail(35);

    if (chmod(p2, 0644) != 0)                       return fail(36);
    if (chown(p2, (unsigned)-1, (unsigned)-1) != 0) return fail(37);

    const char *lnk = "/tmp/libio-c-smoke.link";
    unlink(lnk);
    if (symlink(p2, lnk) != 0)                      return fail(38);
    char lbuf[128] = {0};
    long ln = readlink(lnk, lbuf, sizeof lbuf);
    if (ln <= 0)                                    return fail(39);
    if (lstat(lnk, statbuf) != 0)                   return fail(40);

    unlink(lnk);
    unlink(p2);

    /* v1.4: create a fresh dir with two flat files, then iterate.
     * Expect exactly 4 entries: ".", "..", "one", "two". */
    const char *ird = "/tmp/libio-c-smoke.iter";
    rmdir(ird);                                     /* best-effort */
    if (mkdir(ird, 0755) != 0)                      return fail(41);
    {
        char one[64], two[64];
        snprintf(one, sizeof one, "%s/one", ird);
        snprintf(two, sizeof two, "%s/two", ird);
        int f1 = open(one, O_RDWR | O_CREAT, 0600);
        if (f1 < 0)                                 return fail(42);
        close(f1);
        int f2 = open(two, O_RDWR | O_CREAT, 0600);
        if (f2 < 0)                                 return fail(43);
        close(f2);

        unsigned char iter[4128];
        if (dir_iter_open(iter, ird) != 0)          return fail(44);
        int count = 0;
        int saw_one = 0, saw_two = 0;
        for (;;) {
            char name[256];
            unsigned char type;
            long r = dir_iter_next(iter, name, sizeof name, &type);
            if (r == 0) break;                       /* end */
            if (r < 0)                              return fail(45);
            count++;
            if (memcmp(name, "one", 4) == 0) saw_one = 1;
            if (memcmp(name, "two", 4) == 0) saw_two = 1;
        }
        if (dir_iter_close(iter) != 0)              return fail(46);
        if (count != 4)                             return fail(47);
        if (!saw_one || !saw_two)                   return fail(48);

        unlink(one);
        unlink(two);
        rmdir(ird);
    }

    puts("PASS");
    return 0;
}
