/*
 * c-smoke.c — verify libresolv.a is linkable and callable from C.
 *
 * Compilation-time proof only: this file does not actually
 * perform a DNS query (that would require a live server, which
 * the assembly resolv-smoke already handles). It exercises the
 * archive's key exports with __asm__ labels bound to the bare
 * NASM symbol names and asserts:
 *
 *   * resolv_encode_query(name, id, qtype, out)  — A + AAAA
 *   * resolv_decode_records() rejects a short buffer
 *   * resolv_random() succeeds on a short buffer
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

extern long resolv_encode_query(const char *name, unsigned id, unsigned qtype,
                                 unsigned char *out) __asm__("resolv_encode_query");
extern long resolv_decode_records(const unsigned char *buf, size_t len,
                                   unsigned expected_id, unsigned qtype,
                                   unsigned char *out_buf, size_t max_count)
    __asm__("resolv_decode_records");
extern long resolv_random(void *buf, size_t len) __asm__("resolv_random");

static int fail(int id) {
    fprintf(stderr, "FAIL:%d\n", id);
    return 1;
}

int main(void) {
    unsigned char q[512];

    /* 1: encode succeeds on "a.b" for QTYPE=A. */
    long n = resolv_encode_query("a.b", 0x1234, 1, q);
    if (n <= 0)                                     return fail(1);
    /* Expected length: 12 header + (1+1 + 1+1 + 1) + 4 = 21 */
    if (n != 21)                                    return fail(2);
    /* QTYPE bytes at offset (n-4..n-3) should be 00 01. */
    if (q[n - 4] != 0x00 || q[n - 3] != 0x01)       return fail(3);

    /* 2: same name encoded for AAAA gives the same length but
     * QTYPE = 00 1C at the QTYPE offset. */
    long n2 = resolv_encode_query("a.b", 0x1234, 28, q);
    if (n2 != n)                                    return fail(4);
    if (q[n - 4] != 0x00 || q[n - 3] != 0x1C)       return fail(5);

    /* 3: encode rejects the empty name. */
    if (resolv_encode_query("", 0, 1, q) >= 0)      return fail(6);

    /* 4: decode rejects an obviously-too-short buffer. */
    unsigned char ip[16];
    if (resolv_decode_records(q, 4, 0, 1, ip, 1) >= 0) return fail(7);

    /* 5: random succeeds on a short buffer.
     *
     * Return convention differs by platform: macOS's getentropy
     * returns 0, Linux's getrandom returns the number of bytes
     * read (== len when the pool is initialized). Use the
     * shared -errno convention — non-negative means success. */
    unsigned char rand_buf[8] = {0};
    if (resolv_random(rand_buf, sizeof rand_buf) < 0) return fail(8);

    puts("PASS");
    return 0;
}
