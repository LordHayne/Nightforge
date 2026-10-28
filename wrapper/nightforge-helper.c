// Nightforge Helper: starts one program apart from Nightforge (Sources/Nightforge/Detached.swift).
//
// macOS counts every process an app starts – and everything those start in turn – as part of that
// app, and keeps the Dock icon of a quit app ("exited-with-subordinates") for as long as any of
// them runs. Steam's Wine session, a game, a download or a script that outlives Nightforge would
// leave a second Nightforge icon behind. So they start through this helper instead: Nightforge has
// /usr/bin/open launch it as an app of its own (a launchd job or an NSWorkspace launch would still
// count as Nightforge's), and the helper starts the program and waits for it, so Nightforge still
// learns when it ends and how.
//
// nightforge-helper <run folder>
//   request  from Nightforge, NUL-separated: working folder ("" for none), stdin, stdout and stderr
//            paths (output appended), argument count, arguments (the first is the program),
//            environment count, NAME=value entries. Removed once read.
//   pid      from here, once the program runs: "<helper pid> <program pid>"
//   status   from here, when it has ended: "exit <code>" or "signal <number>"; "error <errno>"
//            when it couldn't start.
//
// Build (arm64, like Nightforge): clang -arch arm64 -mmacosx-version-min=14.0 -O2 -o nightforge-helper nightforge-helper.c

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile pid_t child;

// Quitting the helper quits the program it runs.
static void forward(int sig) {
    if (child > 0) kill(child, sig);
}

// Whole files only: written beside the target and renamed, so Nightforge never reads half of one.
static void put(const char *dir, const char *name, const char *text) {
    char path[4096], temp[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    snprintf(temp, sizeof temp, "%s/.%s", dir, name);
    int fd = open(temp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    size_t length = strlen(text);
    if (write(fd, text, length) == (ssize_t)length) {
        close(fd);
        rename(temp, path);
    } else {
        close(fd);
        unlink(temp);
    }
}

static int failed(const char *dir, int error) {
    char text[32];
    snprintf(text, sizeof text, "error %d\n", error);
    put(dir, "status", text);
    return 1;
}

int main(int argc, char **argv) {
    // Launch Services may put its own -psn_ argument first.
    const char *dir = NULL;
    for (int i = 1; i < argc && !dir; i++)
        if (strncmp(argv[i], "-psn_", 5) != 0) dir = argv[i];
    if (!dir) return 64;

    char path[4096];
    snprintf(path, sizeof path, "%s/request", dir);
    int fd = open(path, O_RDONLY);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) != 0) return failed(dir, errno);
    char *data = malloc((size_t)info.st_size + 1);
    if (!data) return failed(dir, ENOMEM);
    size_t size = 0;
    while (size < (size_t)info.st_size) {
        ssize_t got = read(fd, data + size, (size_t)info.st_size - size);
        if (got <= 0) break;
        size += (size_t)got;
    }
    close(fd);
    unlink(path);  // arguments and environment needn't stay on disk
    data[size] = 0;

    size_t count = 0;
    for (size_t i = 0; i < size; i++) count += data[i] == 0;
    char **fields = calloc(count + 1, sizeof *fields);
    if (!fields) return failed(dir, ENOMEM);
    for (size_t i = 0, start = 0, n = 0; i < size; i++)
        if (data[i] == 0) { fields[n++] = data + start; start = i + 1; }

    if (count < 6) return failed(dir, EINVAL);
    const char *cwd = fields[0], *in = fields[1], *out = fields[2], *err = fields[3];
    size_t nargs = strtoul(fields[4], NULL, 10);
    if (nargs < 1 || 5 + nargs >= count) return failed(dir, EINVAL);
    char **args = fields + 5;
    size_t nenv = strtoul(fields[5 + nargs], NULL, 10);
    if (6 + nargs + nenv > count) return failed(dir, EINVAL);
    char **env = calloc(nenv + 1, sizeof *env);
    if (!env) return failed(dir, ENOMEM);
    memcpy(env, fields + 6 + nargs, nenv * sizeof *env);
    char *program = args[0];
    args[nargs] = NULL;  // overwrites the environment count, already read

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, in, O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 1, out, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (strcmp(out, err) == 0)
        posix_spawn_file_actions_adddup2(&actions, 1, 2);
    else
        posix_spawn_file_actions_addopen(&actions, 2, err, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (*cwd) posix_spawn_file_actions_addchdir_np(&actions, cwd);

    // A clean start, as Nightforge's own Process would give it: no blocked or ignored signals,
    // no descriptors but the three above.
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attributes, &none);
    posix_spawnattr_setsigdefault(&attributes, &all);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT);

    struct sigaction action = {0};
    action.sa_handler = forward;
    action.sa_flags = SA_RESTART;
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGHUP, &action, NULL);

    pid_t pid;
    int error = posix_spawn(&pid, program, &actions, &attributes, args, env);
    if (error != 0) return failed(dir, error);
    child = pid;

    char text[64];
    snprintf(text, sizeof text, "%d %d\n", getpid(), pid);
    put(dir, "pid", text);

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFSIGNALED(status))
        snprintf(text, sizeof text, "signal %d\n", WTERMSIG(status));
    else
        snprintf(text, sizeof text, "exit %d\n", WEXITSTATUS(status));
    put(dir, "status", text);
    return 0;
}
