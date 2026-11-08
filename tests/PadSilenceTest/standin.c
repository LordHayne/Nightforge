// Stands in for winebus: the patch's own pad_silence.h, polled as sdl_bus_wait polls it. --rules checks
// the decisions; otherwise it says "begins" and "ends" on stdout, on the notification names it's given.
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char request[200], answer[200];
#define PAD_SILENCE_NAME request
#define PAD_SILENCE_ANSWER_NAME answer
#include "pad_silence.h"

static int failures;
static void check(int ok, const char *what)
{
    if (!ok)
    {
        failures++;
        printf("✗ %s\n", what);
    }
}

static int rules(void)
{
    struct pad_silence s = {0};
    const uint64_t second = 1000000000ull, now = 1000 * second;

    check(pad_silence_next(&s, 0, now) == PAD_SILENCE_SAME && !s.silent, "never asked: nothing happens");
    check(pad_silence_next(&s, now + 5 * second, now) == PAD_SILENCE_BEGINS && s.silent, "a time ahead: the silence begins");
    check(pad_silence_next(&s, now + 7 * second, now + 2 * second) == PAD_SILENCE_SAME, "moved on: it goes on");
    check(pad_silence_next(&s, 0, now + 3 * second) == PAD_SILENCE_ENDS && !s.silent, "asked to end: it ends");

    pad_silence_next(&s, now + 5 * second, now);
    check(pad_silence_next(&s, now + 5 * second, now + 4 * second) == PAD_SILENCE_SAME, "before the time: still silent");
    check(pad_silence_next(&s, now + 5 * second, now + 5 * second) == PAD_SILENCE_ENDS, "the time is up, nobody renewed it: it ends");

    s = (struct pad_silence){0};
    check(pad_silence_next(&s, now - second, now) == PAD_SILENCE_SAME, "a time in the past: no silence");
    check(pad_silence_next(&s, now + 3600 * second, now) == PAD_SILENCE_SAME, "a time absurdly far off is a mistake: no silence");
    check(pad_silence_next(&s, now + 30 * second, now) == PAD_SILENCE_BEGINS, "up to the longest: silence");
    return failures ? 1 : 0;
}

int main(int argc, char **argv)
{
    struct pad_silence s = {0};

    if (argc == 2 && !strcmp(argv[1], "--rules"))
    {
        int result = rules();
        if (!result) printf("✓ PadSilence rules\n");
        return result;
    }
    if (argc != 3) return 2;
    snprintf(request, sizeof(request), "%s", argv[1]);
    snprintf(answer, sizeof(answer), "%s", argv[2]);
    alarm(60);  // never left behind
    setvbuf(stdout, NULL, _IOLBF, 0);
    printf("up %llu\n", (unsigned long long)clock_gettime_nsec_np(CLOCK_MONOTONIC));
    for (;;)
    {
        enum pad_silence_change change = pad_silence_poll(&s);
        if (change == PAD_SILENCE_BEGINS) printf("begins\n");
        if (change == PAD_SILENCE_ENDS) printf("ends\n");
        usleep(5000);
    }
}
