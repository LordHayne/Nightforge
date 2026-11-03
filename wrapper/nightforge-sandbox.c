// Nightforge Sandbox: starts one program inside a macOS sandbox (Sources/Nightforge/WineSandbox.swift).
//
// Wine is no sandbox: every Windows program sees the whole Mac on Z:, and \\?\unix\ reaches any path
// past the drives. With the switch on, Nightforge starts Wine through this helper, which applies a
// profile that allows everything but a list of places with sign-in data, then becomes the program.
// Everything it starts – Steam's games – stays inside (docs/ENTWURF-LAUFWERKE.md).
//
// This is what /usr/bin/sandbox-exec does, but that one is a protected system program, and macOS
// drops DYLD_* from the environment of those: DYLD_INSERT_LIBRARIES (hide-steam-dock.dylib) would
// be gone, and Steam back in the Dock. It's x86_64 like Wine for the same library, which an arm64
// process couldn't load.
//
// nightforge-sandbox <profile file> <program> [arguments…]
//   Exits 71 without starting anything when the profile can't be applied: switched on, the program
//   never runs outside the sandbox.
//
// Build (x86_64, like Wine): clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -o nightforge-sandbox nightforge-sandbox.c

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// libsystem_sandbox; <sandbox.h> declares them deprecated, which they've been for years, and
// sandbox-exec still uses them.
int sandbox_init(const char *profile, uint64_t flags, char **errorbuf);
void sandbox_free_error(char *errorbuf);

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <profile file> <program> [arguments...]\n", argv[0]);
        return 64;
    }
    FILE *file = fopen(argv[1], "r");
    if (!file) {
        perror(argv[1]);
        return 71;
    }
    char *profile = NULL;
    size_t size = 0;
    FILE *text = open_memstream(&profile, &size);
    char buffer[4096];
    size_t read;
    while ((read = fread(buffer, 1, sizeof buffer, file)) > 0) fwrite(buffer, 1, read, text);
    fclose(file);
    fclose(text);

    char *error = NULL;
    if (sandbox_init(profile, 0, &error) != 0) {
        fprintf(stderr, "nightforge-sandbox: %s\n", error ? error : "the profile was not applied");
        if (error) sandbox_free_error(error);
        return 71;
    }
    free(profile);
    execv(argv[2], argv + 2);
    perror(argv[2]);
    return 127;
}
