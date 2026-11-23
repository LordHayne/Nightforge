// Stands in for Wine's Mac driver (winemac.so): it links AppKit, a Wine process loads it late with dlopen,
// and it does what Wine does with it. For tests/SteamBackgroundTest/run.sh.
#import <AppKit/AppKit.h>

// A window shown: Wine asks for a Dock icon. Answers the activation policy then (0 regular, 1 accessory).
long driver_window(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    return [NSApp activationPolicy];
}

// Wine's Cocoa app starts (from a bundle: a Dock app already). Answers the policy after it.
long driver_launch(void) {
    [NSApplication sharedApplication];
    [NSApp finishLaunching];
    return [NSApp activationPolicy];
}

// A tray icon: "shown"/"hidden" and the name its state is kept by.
const char *driver_tray(void) {
    NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    static char answer[160];
    snprintf(answer, sizeof(answer), "%s %s", item.visible ? "shown" : "hidden", item.autosaveName.UTF8String ?: "-");
    return answer;
}
