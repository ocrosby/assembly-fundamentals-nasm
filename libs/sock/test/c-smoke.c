/*
 * c-smoke.c — verify libsock.a is linkable and callable from C.
 *
 * This is a compatibility smoke, not a coverage test. The primary
 * suite (in NASM, alongside this file) exercises libsock's
 * implementations via the same ABI a NASM consumer uses. This
 * file proves the archive is equally usable from a normal C
 * toolchain, and that a C consumer that lists libsock.a before
 * libc on the link line gets libsock's implementations for the
 * POSIX-named symbols (`socket`, `close`, etc.) rather than libc's.
 *
 * Two portability details worth naming:
 *
 *   * We deliberately do NOT include <arpa/inet.h>. On Darwin it
 *     #defines htons/htonl/ntohs/ntohl as inline
 *     `__DARWIN_OSSwap*` intrinsics; a call through those macros
 *     never touches the libsock symbol at all, defeating the
 *     point of this test. Same concern for <netinet/in.h>.
 *     AF_INET / SOCK_STREAM are hardcoded below to avoid
 *     transitively dragging those headers in.
 *
 *   * Every extern declaration carries an explicit __asm__ label
 *     with the bare symbol name. Mach-O's default C ABI prefixes
 *     symbols with an underscore (`_socket`), but NASM's macho64
 *     output does not add that prefix. Without the __asm__ label
 *     the linker would look for `_socket` and never see libsock's
 *     `socket`. The label is a GCC extension supported by clang
 *     and is a no-op on ELF (where the naming convention already
 *     matches).
 *
 * Compile: cc c-smoke.c ../libsock.a -o c-smoke
 * Run:     ./c-smoke
 *
 * Prints "PASS\n" and exits 0 on success. Prints "FAIL:<n>\n" to
 * stderr and exits 1 on the first failing check.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Hardcoded to avoid <sys/socket.h> and <netinet/in.h>. */
#define AF_INET     2
#define SOCK_STREAM 1

/* libsock symbols, declared manually. The __asm__ labels pin the
 * external symbol name to the bare form NASM emits — matching
 * libsock on both ELF and Mach-O. */
extern uint16_t htons(uint16_t x) __asm__("htons");
extern uint16_t ntohs(uint16_t x) __asm__("ntohs");
extern uint32_t htonl(uint32_t x) __asm__("htonl");
extern uint32_t ntohl(uint32_t x) __asm__("ntohl");

extern int   inet_pton4(const char *src, void *dst)                   __asm__("inet_pton4");
extern int   inet_pton6(const char *src, void *dst)                   __asm__("inet_pton6");
extern char *inet_ntop4(uint32_t src, char *dst, size_t size)         __asm__("inet_ntop4");
extern char *inet_ntop6(const void *src, char *dst, size_t size)      __asm__("inet_ntop6");

extern int socket(int domain, int type, int protocol) __asm__("socket");
extern int close(int fd)                              __asm__("close");

/* v1.1 util helper — compose the four syscalls every TCP server
 * always makes into one call. Return value is either a non-
 * negative fd or a negative errno. */
extern long server_bind_listen(unsigned ip_net,
                                unsigned short port_host,
                                int backlog)
    __asm__("server_bind_listen");

/* v1.2 util helper — outbound counterpart. socket + connect
 * composed into one call. */
extern long client_connect(unsigned ip_net,
                            unsigned short port_host)
    __asm__("client_connect");

static int fail(int id) {
    fprintf(stderr, "FAIL:%d\n", id);
    return 1;
}

int main(void) {
    /* ---- byte-order helpers ---- */
    if (htons(0x1234)     != 0x3412)     return fail(1);
    if (ntohs(0x3412)     != 0x1234)     return fail(2);
    if (htonl(0x12345678) != 0x78563412) return fail(3);
    if (ntohl(0x78563412) != 0x12345678) return fail(4);

    /* ---- inet_pton4 / inet_ntop4 ----
     *
     * inet_pton4 is a libsock-unique name. If the archive is not
     * on the link line, the binary fails to build here — which is
     * itself a useful signal. */
    unsigned char buf4[4];
    if (inet_pton4("192.168.1.42", buf4) != 1) return fail(5);
    if (buf4[0] != 192 || buf4[1] != 168 ||
        buf4[2] != 1   || buf4[3] != 42) return fail(6);

    /* Re-pack the four network-order octets into a u32 so
     * inet_ntop4 can round-trip them. */
    uint32_t src4 = (uint32_t)buf4[0]
                  | ((uint32_t)buf4[1] << 8)
                  | ((uint32_t)buf4[2] << 16)
                  | ((uint32_t)buf4[3] << 24);
    char out4[16];
    if (inet_ntop4(src4, out4, sizeof out4) != out4) return fail(7);
    if (strcmp(out4, "192.168.1.42") != 0) return fail(8);

    /* ---- inet_pton6 / inet_ntop6 ---- */
    unsigned char buf16[16];
    if (inet_pton6("2001:db8::1", buf16) != 1) return fail(9);
    if (buf16[0] != 0x20 || buf16[1] != 0x01) return fail(10);
    if (buf16[2] != 0x0d || buf16[3] != 0xb8) return fail(11);
    for (size_t i = 4; i < 15; i++) {
        if (buf16[i] != 0)                     return fail(12);
    }
    if (buf16[15] != 1)                        return fail(13);

    char out6[46];
    if (inet_ntop6(buf16, out6, sizeof out6) != out6) return fail(14);
    if (strcmp(out6, "2001:db8::1") != 0)             return fail(15);

    /* ---- socket + close: the common-name interop test ----
     *
     * With libsock.a listed before libc on the link line, these
     * calls resolve to libsock's implementations. libc still
     * provides everything libsock does not (printf, main entry,
     * process startup), but for the collision cases the archive
     * wins because the linker pulls its objects in first to
     * satisfy the currently-undefined references. */
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)         return fail(16);
    if (close(fd) != 0) return fail(17);

    /* v1.1: server_bind_listen against INADDR_ANY, kernel-picked
     * port, small backlog. Proves the composed helper links
     * cleanly and returns a positive fd. */
    long sfd = server_bind_listen(0u, 0u, 5);
    if (sfd < 0)                                     return fail(18);
    if (close((int)sfd) != 0)                        return fail(19);

    /* And once more against 127.0.0.1 to verify the ip_net
     * argument path (not just the INADDR_ANY zero-fast-path). */
    long sfd2 = server_bind_listen(0x0100007Fu, 0u, 1);
    if (sfd2 < 0)                                    return fail(20);
    if (close((int)sfd2) != 0)                       return fail(21);

    /* v1.2: client_connect to a port nothing listens on returns
     * a negative errno without leaking the fd. Same close-on-
     * fail contract as server_bind_listen. */
    long cfail = client_connect(0x0100007Fu, 1u);
    if (cfail >= 0)                                  return fail(22);

    puts("PASS");
    return 0;
}
