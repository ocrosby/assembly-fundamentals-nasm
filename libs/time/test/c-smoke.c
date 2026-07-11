/*
 * c-smoke.c — verify libtime.a is linkable and callable from C.
 *
 * Same shape as libs/io/test/c-smoke.c: pin every libtime extern
 * to the bare NASM symbol name via GCC __asm__ labels, and skip
 * the standard headers that would otherwise re-declare the same
 * names with libc-compatible (underscored-on-Mach-O) linkage.
 *
 * Without the labels, clang on Mach-O emits _gettimeofday /
 * _getrusage and the linker silently binds those to libc rather
 * than libtime. v1.0's c-smoke had exactly that bug — it linked
 * cleanly but never called libtime's wrappers on macOS.
 *
 * Compile: cc c-smoke.c ../libtime.a -o c-smoke
 * Run:     ./c-smoke
 */

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Skip <sys/time.h>, <sys/resource.h>, <time.h>: they redeclare
 * gettimeofday / getrusage / time with libc linkage, conflicting
 * with the __asm__-labelled declarations below. Everything the
 * test needs is declared locally instead.
 */

#if defined(__APPLE__)
typedef long time_t_local;
typedef int  suseconds_t_local;
#else
typedef long time_t_local;
typedef long suseconds_t_local;
#endif

struct timeval_local {
    time_t_local      tv_sec;
    suseconds_t_local tv_usec;
};

/* struct rusage's tail differs between platforms; we only touch
 * the two leading timevals (ru_utime, ru_stime) so a 144-byte
 * scratch is safe on both.
 */
struct rusage_scratch {
    struct timeval_local ru_utime;
    struct timeval_local ru_stime;
    long                 pad[16];
};

#define RUSAGE_SELF_LOCAL 0

/* libc's time() is needed only for the ±60s wall-clock
 * cross-check. Declared locally so we can avoid <time.h>.
 */
extern time_t_local time(time_t_local *tloc);

/* libtime symbols — __asm__ labels pin the linker reference to
 * the bare name NASM emits, while local C names avoid any
 * collision with libc prototypes that may have leaked in
 * through indirect includes.
 */
extern int libtime_gettimeofday(struct timeval_local *tv, void *tz)          __asm__("gettimeofday");
extern int libtime_sleep_ms    (unsigned int ms)                             __asm__("sleep_ms");
extern int libtime_getrusage   (int who, struct rusage_scratch *ru)          __asm__("getrusage");

int main(void) {
    struct timeval_local tv;

    int rc = libtime_gettimeofday(&tv, NULL);
    if (rc != 0) {
        fprintf(stderr, "gettimeofday returned %d\n", rc);
        return 1;
    }

    time_t_local now = time(NULL);
    long delta = (long)tv.tv_sec - (long)now;
    if (delta < -60 || delta > 60) {
        fprintf(stderr, "tv_sec=%ld now=%ld delta=%ld\n",
            (long)tv.tv_sec, (long)now, delta);
        return 1;
    }

    if (tv.tv_usec < 0 || tv.tv_usec >= 1000000) {
        fprintf(stderr, "tv_usec=%d invalid\n", (int)tv.tv_usec);
        return 1;
    }

    /* sleep_ms should actually delay — take a before/after
     * gettimeofday and check the elapsed is at least ~20ms
     * (asked for 50ms, allow scheduler slop).
     */
    struct timeval_local before, after;
    libtime_gettimeofday(&before, NULL);
    rc = libtime_sleep_ms(50);
    libtime_gettimeofday(&after, NULL);
    if (rc != 0) {
        fprintf(stderr, "sleep_ms returned %d\n", rc);
        return 1;
    }
    long elapsed_us = (long)(after.tv_sec - before.tv_sec) * 1000000
                    + (long)(after.tv_usec - before.tv_usec);
    if (elapsed_us < 20000) {
        fprintf(stderr, "sleep_ms(50) only elapsed %ld us\n", elapsed_us);
        return 1;
    }
    if (elapsed_us > 2000000) {
        fprintf(stderr, "sleep_ms(50) elapsed %ld us (too long)\n", elapsed_us);
        return 1;
    }

    struct rusage_scratch ru;
    memset(&ru, 0, sizeof(ru));
    rc = libtime_getrusage(RUSAGE_SELF_LOCAL, &ru);
    if (rc != 0) {
        fprintf(stderr, "getrusage returned %d\n", rc);
        return 1;
    }
    if (ru.ru_utime.tv_sec < 0 || ru.ru_utime.tv_usec < 0
        || ru.ru_stime.tv_sec < 0 || ru.ru_stime.tv_usec < 0) {
        fprintf(stderr, "getrusage produced negative CPU time\n");
        return 1;
    }

    puts("PASS");
    return 0;
}
