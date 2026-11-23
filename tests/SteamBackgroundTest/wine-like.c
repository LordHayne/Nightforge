// A process like a Wine process: AppKit only comes with its Mac driver, loaded with dlopen.
//   wine-like appkit              whether AppKit is in the process (no driver loaded): 0 or 1
//   wine-like window|launch|tray DRIVER   what the driver answers, loaded late
// For tests/SteamBackgroundTest/run.sh.
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "appkit")) {
        int found = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++)
            if (strstr(_dyld_get_image_name(i), "/AppKit.framework/")) found = 1;
        printf("%d\n", found);
        return 0;
    }
    if (argc != 3) return 2;
    void *driver = dlopen(argv[2], RTLD_NOW);
    if (!driver) return 3;
    if (!strcmp(argv[1], "window")) printf("%ld\n", ((long (*)(void))dlsym(driver, "driver_window"))());
    else if (!strcmp(argv[1], "launch")) printf("%ld\n", ((long (*)(void))dlsym(driver, "driver_launch"))());
    else printf("%s\n", ((const char *(*)(void))dlsym(driver, "driver_tray"))());
    return 0;
}
