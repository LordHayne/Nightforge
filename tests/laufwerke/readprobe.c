/* What a Windows program under Wine can read of the Mac: tries each path given on the command line
 * (Z:\… through the drive, \\?\unix\… past every drive mapping) and prints "READ <bytes>" or
 * "DENIED <Windows error>" per path, and the drives Wine shows. Exit code 0.
 *
 *   x86_64-w64-mingw32-gcc -O2 -o readprobe.exe readprobe.c
 */
#include <windows.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    char drives[256];
    DWORD length = GetLogicalDriveStringsA(sizeof(drives), drives);
    printf("drives:");
    for (char *drive = drives; drive < drives + length && *drive; drive += strlen(drive) + 1) printf(" %s", drive);
    printf("\n");
    char cwd[MAX_PATH];
    GetCurrentDirectoryA(sizeof(cwd), cwd);
    printf("cwd: %s\n", cwd);
    for (int i = 1; i < argc; i++) {
        HANDLE file = CreateFileA(argv[i], GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
        if (file == INVALID_HANDLE_VALUE) {
            printf("DENIED %lu  %s\n", (unsigned long)GetLastError(), argv[i]);
            continue;
        }
        char buffer[64];
        DWORD read = 0;
        BOOL ok = ReadFile(file, buffer, sizeof(buffer), &read, NULL);
        printf("%s %lu  %s\n", ok ? "READ" : "OPEN-ONLY", (unsigned long)read, argv[i]);
        CloseHandle(file);
    }
    /* Listing Z:\ shows what a program that walks the drives finds there. */
    WIN32_FIND_DATAA found;
    HANDLE list = FindFirstFileA("Z:\\*", &found);
    printf("Z:\\ holds:");
    if (list != INVALID_HANDLE_VALUE) {
        int shown = 0;
        do {
            if (found.cFileName[0] == '.') continue;
            if (shown++ < 12) printf(" [%s]", found.cFileName);
        } while (FindNextFileA(list, &found));
        FindClose(list);
        if (shown > 12) printf(" … (%d in all)", shown);
    }
    printf("\n");
    return 0;
}
