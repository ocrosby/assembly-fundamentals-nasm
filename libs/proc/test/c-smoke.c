/*
 * c-smoke.c — verify libproc.a is linkable and callable from C.
 *
 * Same shape as libs/io/test/c-smoke.c: pin every libproc extern
 * to the bare NASM symbol name via GCC __asm__ labels, and skip
 * the standard headers that would otherwise re-declare the same
 * names with libc-compatible (underscored-on-Mach-O) linkage.
 *
 * Without the labels, clang on Mach-O emits _fork / _wait4 /
 * _getpid / _getppid / _kill and the linker silently binds
 * those to libc rather than libproc — the smoke would pass but
 * never call the archive.
 *
 * Compile: cc c-smoke.c ../libproc.a -o c-smoke
 * Run:     ./c-smoke
 */

#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* Skip <unistd.h>, <sys/wait.h>, <signal.h>: they redeclare
 * the same names with libc linkage. Everything the test needs
 * is declared locally.
 */

typedef int pid_t_local;

/* libproc symbols — __asm__ labels pin references to the bare
 * name NASM emits. */
extern pid_t_local libproc_fork   (void)                                                __asm__("fork");
extern pid_t_local libproc_wait4  (pid_t_local pid, int *wstatus, int options, void *ru) __asm__("wait4");
extern pid_t_local libproc_getpid (void)                                                __asm__("getpid");
extern pid_t_local libproc_getppid(void)                                                __asm__("getppid");
extern int         libproc_kill   (pid_t_local pid, int sig)                            __asm__("kill");

/* Raw _exit(n) — do not call libc's exit() from the child, we
 * do not want atexit handlers or stdio flushes running twice.
 */
static void raw_exit(int code) {
#if defined(__APPLE__)
    __asm__ volatile ("mov $0x2000001, %%eax; syscall" : : "D"(code) : "rax", "rcx", "r11");
#else
    __asm__ volatile ("mov $60, %%eax; syscall" : : "D"(code) : "rax", "rcx", "r11");
#endif
    __builtin_unreachable();
}

int main(void) {
    /* getpid + getppid basic sanity. */
    pid_t_local mypid = libproc_getpid();
    if (mypid <= 0) {
        fprintf(stderr, "getpid returned %d\n", mypid);
        return 1;
    }
    pid_t_local ppid = libproc_getppid();
    if (ppid <= 0) {
        fprintf(stderr, "getppid returned %d\n", ppid);
        return 1;
    }
    if (ppid == mypid) {
        fprintf(stderr, "getppid == getpid (%d)\n", mypid);
        return 1;
    }

    /* fork + child _exit(42) + parent wait4. */
    pid_t_local child = libproc_fork();
    if (child < 0) {
        fprintf(stderr, "fork returned %d\n", child);
        return 1;
    }
    if (child == 0) {
        raw_exit(42);
    }

    int wstatus = 0;
    pid_t_local reaped = libproc_wait4(child, &wstatus, 0, NULL);
    if (reaped != child) {
        fprintf(stderr, "wait4 returned %d (want %d)\n", reaped, child);
        return 1;
    }
    if (wstatus != (42 << 8)) {
        fprintf(stderr, "wstatus=0x%x (want 0x%x)\n", wstatus, 42 << 8);
        return 1;
    }

    /* kill(child, 0) after reap should be -ESRCH (-3). */
    int rc = libproc_kill(child, 0);
    if (rc != -3) {
        fprintf(stderr, "kill(reaped, 0) returned %d (want -3 / -ESRCH)\n", rc);
        return 1;
    }

    puts("PASS");
    return 0;
}
