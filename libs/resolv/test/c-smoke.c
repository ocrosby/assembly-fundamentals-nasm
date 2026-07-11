/*
 * c-smoke.c — verify libresolv.a is linkable and callable from C.
 *
 * Compilation-time proof only: this file does not actually
 * perform a DNS query (that would require a live server, which
 * the assembly resolv-smoke already handles). It exercises the
 * archive's four exports with __asm__ labels bound to the bare
 * NASM symbol names and asserts:
 *
 *   * resolv_encode_query() succeeds on a small hostname
 *   * resolv_decode_response() rejects a 4-byte buffer
 *   * resolv_random() returns 0 for a small buffer
 *
 * If any export were misnamed, the wrong ABI, or absent from
 * the archive, the binary would either fail to link or one of
 * the assertions above would fire. libc's close/unlink are not
 * touched here.
 *
 * Compile: cc c-smoke.c ../libresolv.a ../../sock/libsock.a -o c-smoke
 * Run:     ./c-smoke
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern long resolv_encode_query(const char *name, unsigned id, unsigned char *out) __asm__("resolv_encode_query");
extern long resolv_decode_response(const unsigned char *buf, size_t len,
                                    unsigned expected_id, unsigned char *out_ip)
    __asm__("resolv_decode_response");
extern long resolv_random(void *buf, size_t len) __asm__("resolv_random");

static int fail(int id) {
    fprintf(stderr, "FAIL:%d\n", id);
    return 1;
}

int main(void) {
    unsigned char q[512];

    /* 1: encode succeeds on "a.b" (two 1-char labels). */
    long n = resolv_encode_query("a.b", 0x1234, q);
    if (n <= 0)                                     return fail(1);
    /* Expected length: 12 header + (1+1 + 1+1 + 1) + 4 = 21 */
    if (n != 21)                                    return fail(2);

    /* 2: encode rejects the empty name. */
    if (resolv_encode_query("", 0, q) >= 0)         return fail(3);

    /* 3: decode rejects an obviously-too-short buffer. */
    unsigned char ip[4];
    if (resolv_decode_response(q, 4, 0, ip) >= 0)   return fail(4);

    /* 4: random succeeds on a short buffer.
     *
     * Return convention differs by platform: macOS's getentropy
     * returns 0, Linux's getrandom returns the number of bytes
     * read (== len when the pool is initialized). Use the
     * shared -errno convention — non-negative means success. */
    unsigned char rand_buf[8] = {0};
    if (resolv_random(rand_buf, sizeof rand_buf) < 0) return fail(5);

    puts("PASS");
    return 0;
}
