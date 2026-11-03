/*
 * A legendary that hangs, for EpicTest's check of Legendary.end: it ignores SIGTERM ("polite": it
 * doesn't) and, with "family", first starts a helper of its own kind, the way legendary's downloader
 * runs in processes apart. It waits until it's killed.
 *
 * Usage: stand-in [polite] [family]
 */
#include <signal.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    int polite = 0, family = 0;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "polite") == 0) polite = 1;
        if (strcmp(argv[i], "family") == 0) family = 1;
    }
    if (!polite) signal(SIGTERM, SIG_IGN);
    if (family && fork() == 0) {
        for (;;) pause();
    }
    for (;;) pause();
}
