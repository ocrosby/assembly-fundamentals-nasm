/* c-smoke.c — verify libtime.a is linkable and callable from
 * a C toolchain.
 *
 * The link line lists libtime.a before -lSystem / -lc, so the
 * unresolved reference to gettimeofday resolves to the archive's
 * copy rather than libc's. That is the whole point of the
 * archive existing — a C consumer that wants the raw-syscall
 * implementation can pick it up with a normal link and no
 * source changes.
 *
 * time(NULL) is used as an independent second opinion on the
 * wall clock. It routes through libc (never overridden by
 * libtime v1.0) so the two values come from distinct paths.
 */

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

int main(void) {
    struct timeval tv;

    int rc = gettimeofday(&tv, NULL);
    if (rc != 0) {
        fprintf(stderr, "gettimeofday returned %d\n", rc);
        return 1;
    }

    /* Sanity: within ±60 seconds of libc's time(NULL). Anything
     * outside that window means the wrapper wrote garbage.
     */
    time_t now = time(NULL);
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

    puts("PASS");
    return 0;
}
