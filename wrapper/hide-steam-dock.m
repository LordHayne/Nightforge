// Keeps Steam's own processes out of the Dock when Nightforge runs it in the background.
//
// Wine turns a process into a regular Dock app as soon as it shows any window. Steam's browser
// (steamwebhelper) does that even with -silent, for tiny invisible menu windows. This library is
// loaded into Wine processes via DYLD_INSERT_LIBRARIES and downgrades that request to an accessory
// app – only for Steam's processes, so its dialogs still appear but no Dock icon does. Games keep
// their normal Dock icon.
//
// With Game Mode on, Wine runs from an app bundle (see Engine.installGameBundle), and macOS makes every
// process started from a bundle a Dock app right away, without asking setActivationPolicy:. So
// all of them start as accessory apps, and only a process that shows a window (a game) gets one.
//
// Steam's tray icon stays out of the menu bar too: winemac makes a menu bar item of every tray icon
// (cocoa_status_item.m), one for each Windows Steam that runs – beside Steam for Mac's own, the
// player saw three at once (27.10.2026). Its menu (Store, Friends, Exit) is nothing to click for a
// Steam Nightforge runs in the background. Steam for Mac isn't a Wine process and keeps its own.
//
// Without AppKit of its own (23.11.2026): linked to it, the library brought AppKit – and with it QuartzCore
// and Metal, some 385 libraries – into every Wine process, also the ones that never show a window and so
// never load it: wineserver, services, both winedevice, plugplay, svchost, rpcss, lsass, Steam's service and
// its web helper's wrapper. A Wine session without it started in 0.57 instead of 0.81–1.20 s. AppKit comes
// with Wine's Mac driver (winemac.so, loaded with dlopen) in the processes that show something; the methods
// above are swapped right after that dlopen, by the Objective-C runtime alone, or at the start when AppKit
// is there already. The dlopen in between only looks once whether AppKit came with it.
//
// Build (x86_64, like Wine): with network-order.c and d3dmetal-pace.m, see build.sh (-lobjc, no frameworks).

#import <crt_externs.h>
#import <ctype.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdio.h>
#import <string.h>

// NSApplicationActivationPolicy's values, without AppKit's headers.
enum { PolicyRegular = 0, PolicyAccessory = 1 };

static int isSteamProcess(void) {
    // Wine rewrites argv[0] to the Windows path of the program it's running.
    char **argv = *_NSGetArgv();
    if (!argv || !argv[0]) return 0;
    char program[1024];
    size_t length = 0;
    for (; argv[0][length] && length < sizeof(program) - 1; length++) program[length] = (char)tolower((unsigned char)argv[0][length]);
    program[length] = 0;
    static const char client[] = "\\steam\\steam.exe";
    return strstr(program, "steamwebhelper") || strstr(program, "steamservice")
        || (length >= sizeof(client) - 1 && !strcmp(program + length - (sizeof(client) - 1), client));
}

static BOOL (*originalSetActivationPolicy)(id, SEL, long);
static int wantsDock;

static BOOL nightforgeSetActivationPolicy(id self, SEL _cmd, long policy) {
    if (policy == PolicyRegular) {
        if (isSteamProcess()) policy = PolicyAccessory;
        else wantsDock = 1;
    }
    return originalSetActivationPolicy(self, _cmd, policy);
}

// Started from the bundle, every Wine process – Steam, explorer.exe, services – would be a Dock app from the start.
// It's an accessory app until Wine itself asks for a Dock icon, which it does when a game shows its window
// (Steam's requests are turned down above) – before AppKit's launch and after it, as AppKit's two notifications did.
static void (*originalFinishLaunching)(id, SEL);

static void accessoryUntilAsked(id app) {
    long policy = ((long (*)(id, SEL))objc_msgSend)(app, sel_registerName("activationPolicy"));
    if (!wantsDock && policy == PolicyRegular) originalSetActivationPolicy(app, sel_registerName("setActivationPolicy:"), PolicyAccessory);
}

static void nightforgeFinishLaunching(id self, SEL _cmd) {
    accessoryUntilAsked(self);
    originalFinishLaunching(self, _cmd);
    accessoryUntilAsked(self);
}

static id (*originalStatusItem)(id, SEL, double);
static unsigned long steamItems;

// Hidden under a name of its own: macOS keeps a hidden item's state by that name, in the defaults of
// the Wine bundle Steam shares with the games – so it's never the name a game's first item gets.
static id nightforgeStatusItem(id self, SEL _cmd, double length) {
    id item = originalStatusItem(self, _cmd, length);
    if (item && isSteamProcess()) {
        char name[64];
        snprintf(name, sizeof(name), "nightforge.steam-tray.%lu", steamItems++);
        id string = ((id (*)(id, SEL, const char *))objc_msgSend)((id)objc_getClass("NSString"),
                                                                  sel_registerName("stringWithUTF8String:"), name);
        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setAutosaveName:"), string);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(item, sel_registerName("setVisible:"), NO);
    }
    return item;
}

static pthread_mutex_t swapLock = PTHREAD_MUTEX_INITIALIZER;
static int swapped;

// Once AppKit is in the process, and whole. Not from dyld's word that its images came: its classes aren't known yet
// then, and the Objective-C runtime's own word comes under its lock.
static void swapOnceAppKitIsThere(void) {
    if (__atomic_load_n(&swapped, __ATOMIC_ACQUIRE)) return;
    pthread_mutex_lock(&swapLock);
    Class application = swapped ? Nil : objc_getClass("NSApplication");
    if (application) {
        Class statusBar = objc_getClass("NSStatusBar");
        Method statusItem = statusBar ? class_getInstanceMethod(statusBar, sel_registerName("statusItemWithLength:")) : NULL;
        if (statusItem) originalStatusItem = (void *)method_setImplementation(statusItem, (IMP)nightforgeStatusItem);
        Method policy = class_getInstanceMethod(application, sel_registerName("setActivationPolicy:"));
        Method launch = class_getInstanceMethod(application, sel_registerName("finishLaunching"));
        if (policy && launch) {
            originalSetActivationPolicy = (void *)method_setImplementation(policy, (IMP)nightforgeSetActivationPolicy);
            originalFinishLaunching = (void *)method_setImplementation(launch, (IMP)nightforgeFinishLaunching);
        }
        __atomic_store_n(&swapped, 1, __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&swapLock);
}

static void *nightforgeDlopen(const char *path, int mode) {
    void *handle = dlopen(path, mode);  // the real one: a library's interposing doesn't reach its own calls
    swapOnceAppKitIsThere();
    return handle;
}

__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} interposeDlopen __attribute__((section("__DATA,__interpose"))) = { (const void *)nightforgeDlopen, (const void *)dlopen };

__attribute__((constructor)) static void install(void) {
    swapOnceAppKitIsThere();
}
