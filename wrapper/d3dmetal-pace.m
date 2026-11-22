// Nightforge's frame limit (60 FPS, say) for games on Apple's D3DMetal, which has no switch for one: D3DMetal 3.0
// hands each frame over with -[MTLCommandBuffer presentDrawable:]. DXMT holds the same limit with
// presentDrawable:afterMinimumDuration: (its winemetal.so; d3d11.preferredMaxFrameRate), so here a D3DMetal
// process gets that too: each frame is shown no sooner than 1/limit seconds after the one before, on the
// display's beat. For that beat to count, the layer's display sync stays on.
//
// Only in a process that loads D3DMetal.framework, with D3DM_MAX_FPS in its environment, a permit file that
// Nightforge wrote for this one game's start (never for one with an anti-cheat or a cheat protection of its own),
// and Metal's class and methods there. Anything missing: nothing is changed, not even the sync. One line in the
// log when it takes hold. docs/ENTWURF-D3DMETAL-FPS.md.

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <crt_externs.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "d3dmetal-pace.h"

static int paceLimit;
static void (*originalPresent)(id, SEL, id);
static void (*originalSetDisplaySync)(id, SEL, BOOL);

static void pacedPresent(id self, SEL _cmd, id drawable) {
    ((void (*)(id, SEL, id, CFTimeInterval))objc_msgSend)(self, @selector(presentDrawable:afterMinimumDuration:),
                                                          drawable, 1.0 / paceLimit);
}

static void syncedSetDisplaySync(id self, SEL _cmd, BOOL enabled) {
    originalSetDisplaySync(self, _cmd, YES);
}

static char *permitText(void) {
    const char *home = getenv("HOME");
    if (!home) return NULL;
    char path[1024];
    if (snprintf(path, sizeof path, "%s/Library/Application Support/Nightforge/d3dmetal-pace", home) >= (int)sizeof path) return NULL;
    FILE *file = fopen(path, "r");
    if (!file) return NULL;
    char *text = calloc(1, 2048);
    if (text) fread(text, 1, 2047, file);
    fclose(file);
    return text;
}

static void takeHold(void) {
    char **argv = *_NSGetArgv();
    char *permit = permitText();
    int limit = nightforge_pace_limit(getenv("D3DM_MAX_FPS"), permit, argv ? argv[0] : NULL);
    free(permit);
    if (!limit) return;
    Class buffer = objc_getClass("_MTLCommandBuffer");
    Method present = buffer ? class_getInstanceMethod(buffer, @selector(presentDrawable:)) : NULL;
    Method sync = class_getInstanceMethod([CAMetalLayer class], @selector(setDisplaySyncEnabled:));
    if (!present || !sync || ![buffer instancesRespondToSelector:@selector(presentDrawable:afterMinimumDuration:)]) return;
    paceLimit = limit;
    originalPresent = (void *)method_setImplementation(present, (IMP)pacedPresent);
    originalSetDisplaySync = (void *)method_setImplementation(sync, (IMP)syncedSetDisplaySync);
    fprintf(stderr, "info:  [nightforge] D3DMetal frame limit %d FPS: each frame shown no sooner than %.2f ms after the last, as DXMT does\n",
            limit, 1000.0 / limit);
}

static void imageAdded(const struct mach_header *header, intptr_t slide) {
    static int seen = 0;
    if (seen) return;
    Dl_info info;
    if (!dladdr(header, &info) || !nightforge_is_d3dmetal(info.dli_fname)) return;
    seen = 1;
    // After dyld is done with the image and Metal's classes are ready: never from inside its callback.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ takeHold(); });
}

__attribute__((constructor)) static void watchForD3DMetal(void) {
    // Not in a process without a limit to hold: Steam and every game on another layer go without even the watch.
    if (!getenv("D3DM_MAX_FPS")) return;
    _dyld_register_func_for_add_image(imageAdded);
}
