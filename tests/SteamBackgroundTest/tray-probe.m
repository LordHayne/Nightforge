// Makes a menu bar item as winemac does for a tray icon (cocoa_status_item.m) and says whether it's
// shown, with the name it got; removed again before anything is drawn. tests/SteamBackgroundTest/run.sh
// runs it with hide-steam-dock.dylib loaded, once as Steam and once as a game.
#import <AppKit/AppKit.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
        if (!item) {
            puts("no item");
            return 0;
        }
        printf("%s %s\n", item.isVisible ? "shown" : "hidden", item.autosaveName.UTF8String ?: "-");
        [[NSStatusBar systemStatusBar] removeStatusItem:item];
    }
    return 0;
}
