/*
 * For probe.sh: the environment a running process started with, read like Nightforge does
 * (DockHider.startValue, KERN_PROCARGS2), so the probe's steam.exe call runs with exactly what Nightforge gave the
 * running Steam. Writes NUL-separated "NAME=value" entries to stdout; nothing is printed to a terminal by probe.sh.
 *
 * Usage: steam-env <pid>          Exit: 0 written, 1 not readable, 64 usage
 * Build: clang -O2 -Wall -o steam-env steam-env.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

int main(int argc, char **argv)
{
    if (argc != 2) return 64;
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, atoi(argv[1]) };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < 8) return 1;
    char *buffer = malloc(size);
    if (!buffer || sysctl(mib, 3, buffer, &size, NULL, 0) != 0) return 1;
    /* argc, the executable's path, padding, the arguments, then the environment. Wine moves its arguments
       together in place, so entries are told apart by their form ("NAME=…" after the arguments), as in
       DockHider.startValue: everything after the path that has a '=' before any space or backslash. */
    char *p = buffer + sizeof(int), *end = buffer + size;
    p += strnlen(p, (size_t)(end - p));
    int written = 0;
    while (p < end) {
        while (p < end && *p == '\0') ++p;
        if (p >= end) break;
        size_t length = strnlen(p, (size_t)(end - p));
        const char *equals = memchr(p, '=', length);
        size_t name = equals ? (size_t)(equals - p) : 0;
        int plain = name > 0;
        for (size_t i = 0; i < name && plain; ++i) {
            char c = p[i];
            plain = (c == '_') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (i > 0 && c >= '0' && c <= '9');
        }
        if (plain) {
            fwrite(p, 1, length + 1, stdout);
            ++written;
        }
        p += length;
    }
    free(buffer);
    return written ? 0 : 1;
}
