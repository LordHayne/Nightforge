/*
 * Presses "Play!" in Unity's configuration window, for Nightforge (UnityDialog.swift).
 *
 * Unity games up to 2019.2 can open a window "<product> Configuration" before they start (screen,
 * quality, the picture in <Game>_Data/ScreenSelector.bmp) and wait there for "Play!". A controller
 * can't press it, and no start option skips it (Unity only has -show-screen-selector, which forces
 * it). Nightforge starts this program beside such a game, in the same Wine session: it looks for that
 * window, presses its button and ends; without one in the time given it ends as well. All of it is
 * Win32 inside the Wine session, so the Mac's accessibility permission isn't needed.
 *
 * Only that window: a dialog (class #32770) that belongs to one of the game's programs, whose title is
 * the product's name (as <Game>_Data/app.info has it; spaces and case aside) and " Configuration", and
 * which has a "Play!" push button. Nothing else is touched.
 *
 * Usage: unity-play.exe <seconds> <program.exe> <product> [<program.exe> <product> ...]
 * Exit:  0 pressed, 1 no such window in time, 2 the window didn't take the press, 64 usage
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode -mwindows -static -o unity-play.exe unity-play.c
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>
#include <wctype.h>

#define MAX_GAMES 16
#define SUFFIX L" Configuration"

struct game {
    const wchar_t *program;  /* "TheForest.exe" */
    const wchar_t *product;  /* "TheForest" */
};

static struct game games[MAX_GAMES];
static int game_count;

/* "TheForest" and "The Forest" alike: spaces and case don't count. */
static int same_name(const wchar_t *a, size_t a_length, const wchar_t *b)
{
    const wchar_t *a_end = a + a_length;
    for (;;) {
        while (a < a_end && *a == L' ') ++a;
        while (*b == L' ') ++b;
        if (a == a_end || !*b) return a == a_end && !*b;
        if (towlower(*a) != towlower(*b)) return 0;
        ++a;
        ++b;
    }
}

static const wchar_t *base_name(const wchar_t *path)
{
    const wchar_t *name = path;
    for (const wchar_t *c = path; *c; ++c) {
        if (*c == L'\\' || *c == L'/') name = c + 1;
    }
    return name;
}

/* The game whose program owns the window, or NULL. */
static const struct game *owner(HWND window)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (!pid) return NULL;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return NULL;
    wchar_t path[MAX_PATH * 2];
    DWORD size = sizeof(path) / sizeof(path[0]);
    BOOL found = QueryFullProcessImageNameW(process, 0, path, &size);
    CloseHandle(process);
    if (!found) return NULL;
    const wchar_t *name = base_name(path);
    for (int i = 0; i < game_count; ++i) {
        if (lstrcmpiW(name, games[i].program) == 0) return &games[i];
    }
    return NULL;
}

static BOOL CALLBACK find_play(HWND child, LPARAM result)
{
    wchar_t text[16];
    if (GetClassNameW(child, text, 16) == 0 || lstrcmpiW(text, L"Button") != 0) return TRUE;
    LONG type = GetWindowLongW(child, GWL_STYLE) & BS_TYPEMASK;
    if (type != BS_PUSHBUTTON && type != BS_DEFPUSHBUTTON) return TRUE;
    if (GetWindowTextW(child, text, 16) == 0 || wcscmp(text, L"Play!") != 0) return TRUE;
    *(HWND *)result = child;
    return FALSE;
}

struct found {
    HWND dialog;
    HWND play;
    wchar_t title[512];
};

static BOOL CALLBACK find_dialog(HWND window, LPARAM result)
{
    if (!IsWindowVisible(window)) return TRUE;
    wchar_t text[512];
    if (GetClassNameW(window, text, 512) == 0 || wcscmp(text, L"#32770") != 0) return TRUE;
    int length = GetWindowTextW(window, text, 512);
    size_t suffix = wcslen(SUFFIX);
    if (length <= (int)suffix || wcscmp(text + length - suffix, SUFFIX) != 0) return TRUE;
    const struct game *game = owner(window);
    if (!game || !same_name(text, length - suffix, game->product)) return TRUE;
    HWND play = NULL;
    EnumChildWindows(window, find_play, (LPARAM)&play);
    if (!play || !IsWindowEnabled(play)) return TRUE;
    struct found *found = (struct found *)result;
    found->dialog = window;
    found->play = play;
    wcscpy(found->title, text);
    return FALSE;
}

/* Whether the dialog closes within `milliseconds`. */
static int gone(HWND dialog, DWORD milliseconds)
{
    for (DWORD waited = 0; waited <= milliseconds; waited += 100) {
        if (!IsWindow(dialog) || !IsWindowVisible(dialog)) return 1;
        Sleep(100);
    }
    return 0;
}

/* A line for Nightforge's game log, when it gave this program one. */
static void note(const wchar_t *what, const struct found *found)
{
    HANDLE log = GetStdHandle(STD_ERROR_HANDLE);
    if (log == NULL || log == INVALID_HANDLE_VALUE) return;
    wchar_t line[768];
    int length = _snwprintf(line, 768, L"info:  [nightforge] Unity's window%ls%ls%ls: %ls\n",
                            found ? L" \"" : L"", found ? found->title : L"", found ? L"\"" : L"", what);
    if (length <= 0) return;
    char utf8[1536];
    int bytes = WideCharToMultiByte(CP_UTF8, 0, line, length, utf8, sizeof(utf8), NULL, NULL);
    DWORD written;
    if (bytes > 0) WriteFile(log, utf8, (DWORD)bytes, &written, NULL);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR cmdline, int show)
{
    (void)instance; (void)previous; (void)cmdline; (void)show;

    int count = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!argv || count < 4 || (count - 2) % 2 != 0 || (count - 2) / 2 > MAX_GAMES) return 64;
    wchar_t *end = NULL;
    long seconds = wcstol(argv[1], &end, 10);
    if (*end || seconds <= 0 || seconds > 3600) return 64;
    for (int i = 2; i + 1 < count; i += 2) {
        if (!*argv[i] || !*argv[i + 1]) return 64;
        games[game_count].program = argv[i];
        games[game_count].product = argv[i + 1];
        ++game_count;
    }

    ULONGLONG deadline = GetTickCount64() + (ULONGLONG)seconds * 1000;
    HWND seen = NULL;
    while (GetTickCount64() < deadline) {
        struct found found = { NULL, NULL, L"" };
        EnumWindows(find_dialog, (LPARAM)&found);
        /* Pressed on the second sight, half a second on: the dialog has filled its lists by then. */
        if (found.dialog && found.dialog == seen) {
            DWORD_PTR answer;
            SendMessageTimeoutW(found.play, BM_CLICK, 0, 0, SMTO_ABORTIFHUNG, 5000, &answer);
            if (gone(found.dialog, 3000)) {
                note(L"pressed Play!", &found);
                return 0;
            }
            /* The click didn't land (a dialog in the background, say): the button's own command. */
            PostMessageW(found.dialog, WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(found.play), BN_CLICKED),
                         (LPARAM)found.play);
            if (gone(found.dialog, 3000)) {
                note(L"pressed Play! (by its command)", &found);
                return 0;
            }
            note(L"didn't take Play!", &found);
            return 2;
        }
        seen = found.dialog;
        Sleep(500);
    }
    note(L"didn't come up", NULL);
    return 1;
}
