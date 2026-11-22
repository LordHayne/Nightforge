// Unix side: the environment a process started with (KERN_PROCARGS2), as DockHider.startValue reads it.
// procenv <pid> <name>...
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
int main(int argc, char **argv) {
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, atoi(argv[1]) };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0) { perror("size"); return 1; }
    char *buf = malloc(size);
    if (sysctl(mib, 3, buf, &size, NULL, 0) != 0) { perror("read"); return 1; }
    for (int i = 2; i < argc; i++) {
        size_t len = strlen(argv[i]);
        const char *found = NULL;
        for (char *p = buf + 4; p < buf + size; p += strlen(p) + 1)
            if (!strncmp(p, argv[i], len) && p[len] == '=') found = p;
        if (found) printf("unix %s\n", found); else printf("unix %s=(none)\n", argv[i]);
    }
    return 0;
}
