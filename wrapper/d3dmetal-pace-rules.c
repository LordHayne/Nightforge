// The rules of d3dmetal-pace.m, apart so a test can run them on made-up values (tests/D3DMetalPaceTest).
#include <ctype.h>
#include <string.h>
#include "d3dmetal-pace.h"

static int parseLimit(const char *text, const char **end) {
    if (!text || !isdigit((unsigned char)*text)) return 0;
    long value = 0;
    while (isdigit((unsigned char)*text) && value <= 1000) value = value * 10 + (*text++ - '0');
    if (end) *end = text;
    return value >= 1 && value <= 1000 ? (int)value : 0;
}

static char folded(char c) { return c == '/' ? '\\' : (char)tolower((unsigned char)c); }

int nightforge_pace_limit(const char *limit, const char *permit, const char *program) {
    const char *rest = NULL;
    int wanted = parseLimit(limit, &rest);
    if (!wanted || *rest) return 0;
    if (!permit || !program) return 0;
    int permitted = parseLimit(permit, &rest);
    if (permitted != wanted || *rest != '\n') return 0;
    const char *folder = rest + 1;
    size_t length = strcspn(folder, "\n");
    while (length > 0 && (folder[length - 1] == '\\' || folder[length - 1] == '/' || folder[length - 1] == '\r')) length--;
    // A drive and a folder at the least ("C:\x"): never a whole drive.
    if (length < 4 || folder[1] != ':') return 0;
    for (size_t i = 0; i < length; i++) {
        if (!program[i] || folded(program[i]) != folded(folder[i])) return 0;
    }
    return program[length] == '\\' || program[length] == '/' ? wanted : 0;
}

int nightforge_is_d3dmetal(const char *image) {
    return image && strstr(image, "/D3DMetal.framework/") != NULL;
}
