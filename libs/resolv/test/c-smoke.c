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

/* v1.3: v6 hosts + hostname entry points. Link-time-only check —
 * the smoke test does not exercise them against real files. */
extern long resolv_hosts_lookup6(const char *path, const char *name,
                                  unsigned char *out16) __asm__("resolv_hosts_lookup6");
extern long resolv_hostname_at6(const char *hosts, const char *conf,
                                 const char *name,
                                 unsigned char *out16) __asm__("resolv_hostname_at6");
extern long resolv_hostname6(const char *name,
                              unsigned char *out16) __asm__("resolv_hostname6");

/* v1.4: multi-nameserver enumeration. Each entry is 8 bytes —
 * u32 ip (net order), u16 port (host order), u16 flags (0). */
extern long resolv_conf_read_all(const char *path, void *out_buf,
                                  size_t max_count) __asm__("resolv_conf_read_all");

/* v1.5: search-domain enumeration. Returns count of NUL-
 * terminated domains packed back-to-back in out_buf, or a
 * negative errno on failure. */
extern long resolv_conf_read_search(const char *path, char *out_buf,
                                     size_t capacity) __asm__("resolv_conf_read_search");

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

    /* 6: v6 hosts lookup against a missing file → negative errno.
     * Link-time check — the archive must export the symbol and
     * the function must respect the -errno convention.
     * We assert only "returns negative", since the exact errno
     * (-ENOENT vs -EACCES) depends on the platform. */
    unsigned char v6[16] = {0};
    if (resolv_hosts_lookup6("/proc/libresolv/does-not-exist-",
                              "any.test", v6) >= 0) return fail(9);

    /* 7: v6 hostname_at against a missing hosts + missing conf
     * returns some negative errno. Same link-time-only intent. */
    if (resolv_hostname_at6("/proc/libresolv/does-not-exist-",
                             "/proc/libresolv/does-not-exist-",
                             "any.test", v6) >= 0) return fail(10);

    /* 8: link-time reference to resolv_hostname6. We do not call
     * it (would hit real /etc/resolv.conf on the CI runner). A
     * dead reference through a volatile function pointer is
     * enough to fail the link if the symbol is missing. */
    long (* volatile sink)(const char *, unsigned char *) = resolv_hostname6;
    (void)sink;

    /* 9: resolv_conf_read_all on a missing file returns a
     * negative errno (matches the -read convention). Proves
     * the v1.4 symbol is exported and respects the errno
     * contract. */
    unsigned char entries[64] = {0};
    if (resolv_conf_read_all("/proc/libresolv/does-not-exist-",
                              entries, 8) >= 0) return fail(11);

    /* 10: resolv_conf_read_search on a missing file also
     * returns a negative errno. Link-time check for v1.5. */
    char search[128] = {0};
    if (resolv_conf_read_search("/proc/libresolv/does-not-exist-",
                                 search, sizeof search) >= 0) return fail(12);

    puts("PASS");
    return 0;
}
