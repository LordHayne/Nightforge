// The rules of wrapper/d3dmetal-pace.m on made-up values: when a process gets Nightforge's frame limit on D3DMetal.
#include <stdio.h>
#include "d3dmetal-pace.h"

static int failures = 0;

static void check(int condition, const char *message) {
    if (!condition) {
        failures++;
        printf("✗ %s\n", message);
    }
}

int main(void) {
    const char *permit = "60\nC:\\Program Files (x86)\\Steam\\steamapps\\common\\Black Myth\n";
    const char *game = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Black Myth\\b1\\Binaries\\Win64\\b1.exe";
    check(nightforge_pace_limit("60", permit, game) == 60, "limit, permit and the game's program agree: 60");
    check(nightforge_pace_limit("60", permit, "c:/program files (x86)/steam/steamapps/common/black myth/b1.exe") == 60,
          "case and slashes don't count");
    check(nightforge_pace_limit("60", "60\nC:\\Program Files (x86)\\Steam\\steamapps\\common\\Black Myth\\\n", game) == 60,
          "a folder with a backslash at its end");
    check(nightforge_pace_limit("60", "60\nZ:\\Volumes\\Games\\common\\Black Myth\n",
                                "Z:\\Volumes\\Games\\common\\Black Myth\\b1.exe") == 60, "a game on a drive (Z:)");

    // Anything missing or not agreeing: no limit, nothing hooked.
    check(nightforge_pace_limit(NULL, permit, game) == 0, "no D3DM_MAX_FPS: nothing");
    check(nightforge_pace_limit("", permit, game) == 0, "an empty D3DM_MAX_FPS: nothing");
    check(nightforge_pace_limit("60", NULL, game) == 0, "no permit (a game with an anti-cheat, or none written): nothing");
    check(nightforge_pace_limit("60", "", game) == 0, "an empty permit: nothing");
    check(nightforge_pace_limit("60", permit, NULL) == 0, "no program name: nothing");
    check(nightforge_pace_limit("60", "30\nC:\\Program Files (x86)\\Steam\\steamapps\\common\\Black Myth\n", game) == 0,
          "the permit names another limit (a start before this one): nothing");
    check(nightforge_pace_limit("60", permit, "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Overwatch\\Overwatch.exe") == 0,
          "another game than the permit's (Steam's environment from the game before): nothing");
    check(nightforge_pace_limit("60", permit, "C:\\Program Files (x86)\\Steam\\steam.exe") == 0, "Steam itself: nothing");
    check(nightforge_pace_limit("60", permit, "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Black Myth 2\\b2.exe") == 0,
          "a folder whose name only begins like the permit's: nothing");
    check(nightforge_pace_limit("60", permit, "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Black Myth") == 0,
          "the folder itself is no program: nothing");
    check(nightforge_pace_limit("60", "60\nC:\\\n", "C:\\anything.exe") == 0, "a whole drive as the folder: nothing");
    check(nightforge_pace_limit("60", "60\nGames\n", "Games\\x.exe") == 0, "a folder without a drive: nothing");
    check(nightforge_pace_limit("0", "0\nC:\\Games\\X\n", "C:\\Games\\X\\x.exe") == 0, "limit 0: nothing");
    check(nightforge_pace_limit("1001", "1001\nC:\\Games\\X\n", "C:\\Games\\X\\x.exe") == 0, "past 1000: nothing");
    check(nightforge_pace_limit("60x", "60\nC:\\Games\\X\n", "C:\\Games\\X\\x.exe") == 0, "not a number: nothing");
    check(nightforge_pace_limit("60", "60 C:\\Games\\X\n", "C:\\Games\\X\\x.exe") == 0, "a permit in another shape: nothing");
    check(nightforge_pace_limit("99999999999999999999", "60\nC:\\Games\\X\n", "C:\\Games\\X\\x.exe") == 0, "a huge number: nothing");

    check(nightforge_is_d3dmetal("/x/Wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal"), "D3DMetal.framework is D3DMetal");
    check(!nightforge_is_d3dmetal("/x/graphics/x86_64-unix/winemetal.so"), "DXMT's winemetal.so isn't");
    check(!nightforge_is_d3dmetal("/System/Library/Frameworks/Metal.framework/Versions/A/Metal"), "Metal isn't");
    check(!nightforge_is_d3dmetal(NULL), "no path isn't");

    printf(failures ? "%d rule check(s) failed\n" : "✓ the rules: limit, permit and program have to agree\n", failures);
    return failures ? 1 : 0;
}
