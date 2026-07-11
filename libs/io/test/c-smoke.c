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

/* libc symbols — no __asm__ label, so clang emits the default
 * underscored form (_close, _unlink) that libSystem provides.
 * libio does not export these; a consumer that wants a bare
 * close() links libsock, whose close.o defines it. */
extern int close(int fd);
extern int unlink(const char *path);

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

    /* Best-effort cleanup — we deliberately do not link libio's
     * unlink because libio does not export one (yet). Use the
     * libc unlink so a partial-failure test still cleans up. */
    unlink(path);

    puts("PASS");
    return 0;
}
