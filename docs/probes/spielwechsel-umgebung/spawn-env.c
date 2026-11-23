/*
 * Probe for docs/ENTWURF-SPIELWECHSEL.md: can the environment a game starts with be set where its parent (steam.exe)
 * starts it, on the Unix side, so Rosetta, Wine and D3DMetal see it – without restarting the parent?
 *
 * Loaded into every Wine process through DYLD_INSERT_LIBRARIES (as hide-steam-dock.dylib is), it interposes
 * posix_spawn, posix_spawnp and execve. When the new process's arguments name NF_SPAWN_MATCH (here: child.exe), it
 * adds or removes ROSETTA_ADVERTISE_AVX (NF_SPAWN_AVX=1 or 0) and adds NF_PROBE=spawn. Every call it sees is noted
 * on stderr: which function, whether it matched. Not part of Nightforge.
 *
 * Build: clang -arch x86_64 -dynamiclib -O2 -Wall -o spawn-env.dylib spawn-env.c
 */
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int matches(char *const argv[]) {
    const char *match = getenv("NF_SPAWN_MATCH");
    if (!match || !argv) return 0;
    for (int i = 0; argv[i]; i++) if (strstr(argv[i], match)) return 1;
    return 0;
}

/* envp with ROSETTA_ADVERTISE_AVX as NF_SPAWN_AVX says, and NF_PROBE=spawn. Leaks: the process execs or ends. */
static char **adjusted(char *const envp[]) {
    size_t count = 0;
    while (envp && envp[count]) count++;
    char **out = calloc(count + 3, sizeof(char *));
    if (!out) return (char **)envp;
    size_t n = 0;
    for (size_t i = 0; i < count; i++) {
        if (!strncmp(envp[i], "ROSETTA_ADVERTISE_AVX=", 22) || !strncmp(envp[i], "NF_PROBE=", 9)) continue;
        out[n++] = envp[i];
    }
    const char *avx = getenv("NF_SPAWN_AVX");
    if (avx && !strcmp(avx, "1")) out[n++] = "ROSETTA_ADVERTISE_AVX=1";
    out[n++] = "NF_PROBE=spawn";
    out[n] = NULL;
    return out;
}

static int my_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                          const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    int hit = matches(argv);
    fprintf(stderr, "spawn-env: posix_spawn %s match=%d\n", path ? path : "?", hit);
    return posix_spawn(pid, path, actions, attr, argv, hit ? adjusted(envp) : envp);
}

static int my_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                           const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    int hit = matches(argv);
    fprintf(stderr, "spawn-env: posix_spawnp %s match=%d\n", file ? file : "?", hit);
    return posix_spawnp(pid, file, actions, attr, argv, hit ? adjusted(envp) : envp);
}

static int my_execve(const char *path, char *const argv[], char *const envp[]) {
    int hit = matches(argv);
    fprintf(stderr, "spawn-env: execve %s match=%d\n", path ? path : "?", hit);
    return execve(path, argv, hit ? adjusted(envp) : envp);
}

__attribute__((used)) static const struct { const void *replacement, *original; } interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)my_posix_spawn, (const void *)posix_spawn },
    { (const void *)my_posix_spawnp, (const void *)posix_spawnp },
    { (const void *)my_execve, (const void *)execve },
};
