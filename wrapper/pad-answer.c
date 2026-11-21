/*
 * Answers a Windows game's question with the controller, for Nightforge (PadAnswer.swift).
 *
 * A game can stop before its first picture and ask something in a plain Windows dialog. A pressed A or
 * B reaches this program, which presses the matching button in that dialog and ends. All of it is
 * Win32 inside the Wine session, so the Mac's accessibility permission isn't needed.
 *
 * Only a visible dialog (class #32770) with a push button, the frontmost first, and none of Steam's
 * or Wine's own. Nothing is looked for or waited for beyond that one press: the player asked for it.
 *
 * ok:     the dialog's default button, else OK, Yes or Retry, else its only button.
 * cancel: Cancel, No or Abort, else what Esc sends a dialog.
 *
 * Usage: pad-answer.exe ok|cancel
 * Exit:  0 pressed, 1 no such dialog, 2 the dialog didn't take the press, 64 usage
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode -mwindows -static -o pad-answer.exe pad-answer.c
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>

static const wchar_t *const not_the_game[] = {
    L"steam.exe", L"steamwebhelper.exe", L"steamerrorreporter.exe", L"steamservice.exe", L"explorer.exe", L"services.exe",
    L"winedevice.exe", L"plugplay.exe", L"rpcss.exe", L"svchost.exe", L"conhost.exe", L"start.exe", L"pad-answer.exe",
    L"unity-play.exe",
};

static const wchar_t *base_name(const wchar_t *path)
{
    const wchar_t *name = path;
    for (const wchar_t *c = path; *c; ++c) {
        if (*c == L'\\' || *c == L'/') name = c + 1;
    }
    return name;
}

static int belongs_to_the_game(HWND window)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (!pid) return 0;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return 0;
    wchar_t path[MAX_PATH * 2];
    DWORD size = sizeof(path) / sizeof(path[0]);
    BOOL found = QueryFullProcessImageNameW(process, 0, path, &size);
    CloseHandle(process);
    if (!found) return 0;
    const wchar_t *name = base_name(path);
    for (size_t i = 0; i < sizeof(not_the_game) / sizeof(not_the_game[0]); ++i) {
        if (lstrcmpiW(name, not_the_game[i]) == 0) return 0;
    }
    return 1;
}

struct buttons {
    HWND first;
    int count;
};

static BOOL CALLBACK count_button(HWND child, LPARAM result)
{
    wchar_t name[16];
    if (GetClassNameW(child, name, 16) == 0 || lstrcmpiW(name, L"Button") != 0) return TRUE;
    LONG type = GetWindowLongW(child, GWL_STYLE) & BS_TYPEMASK;
    if ((type != BS_PUSHBUTTON && type != BS_DEFPUSHBUTTON) || !IsWindowVisible(child) || !IsWindowEnabled(child)) return TRUE;
    struct buttons *found = (struct buttons *)result;
    if (!found->first) found->first = child;
    ++found->count;
    return TRUE;
}

static BOOL CALLBACK find_dialog(HWND window, LPARAM result)
{
    if (!IsWindowVisible(window)) return TRUE;
    wchar_t name[16];
    if (GetClassNameW(window, name, 16) == 0 || wcscmp(name, L"#32770") != 0) return TRUE;
    struct buttons buttons = { NULL, 0 };
    EnumChildWindows(window, count_button, (LPARAM)&buttons);
    if (!buttons.count || !belongs_to_the_game(window)) return TRUE;
    *(HWND *)result = window;
    return FALSE;
}

/* The enabled, visible button with this id in the dialog, or NULL. */
static HWND button(HWND dialog, int id)
{
    HWND item = GetDlgItem(dialog, id);
    return item && IsWindowVisible(item) && IsWindowEnabled(item) ? item : NULL;
}

static HWND first_of(HWND dialog, const int *ids, size_t count)
{
    for (size_t i = 0; i < count; ++i) {
        HWND item = button(dialog, ids[i]);
        if (item) return item;
    }
    return NULL;
}

static HWND ok_button(HWND dialog)
{
    LRESULT standard = SendMessageW(dialog, DM_GETDEFID, 0, 0);
    if (HIWORD(standard) == DC_HASDEFID) {
        HWND item = button(dialog, LOWORD(standard));
        if (item) return item;
    }
    static const int ids[] = { IDOK, IDYES, IDRETRY };
    HWND item = first_of(dialog, ids, sizeof(ids) / sizeof(ids[0]));
    if (item) return item;
    struct buttons buttons = { NULL, 0 };
    EnumChildWindows(dialog, count_button, (LPARAM)&buttons);
    return buttons.count == 1 ? buttons.first : NULL;
}

static HWND cancel_button(HWND dialog)
{
    static const int ids[] = { IDCANCEL, IDNO, IDABORT };
    return first_of(dialog, ids, sizeof(ids) / sizeof(ids[0]));
}

static int gone(HWND dialog, DWORD milliseconds)
{
    for (DWORD waited = 0; waited <= milliseconds; waited += 100) {
        if (!IsWindow(dialog) || !IsWindowVisible(dialog)) return 1;
        Sleep(100);
    }
    return 0;
}

static int press(HWND dialog, HWND item)
{
    DWORD_PTR answer;
    SendMessageTimeoutW(item, BM_CLICK, 0, 0, SMTO_ABORTIFHUNG, 3000, &answer);
    if (gone(dialog, 1500)) return 1;
    /* The click didn't land (a dialog in the background, say): the button's own command. */
    PostMessageW(dialog, WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(item), BN_CLICKED), (LPARAM)item);
    return gone(dialog, 1500);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR cmdline, int show)
{
    (void)instance; (void)previous; (void)cmdline; (void)show;

    int count = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!argv || count != 2) return 64;
    int ok = wcscmp(argv[1], L"ok") == 0;
    if (!ok && wcscmp(argv[1], L"cancel") != 0) return 64;

    HWND dialog = NULL;
    EnumWindows(find_dialog, (LPARAM)&dialog);
    if (!dialog) return 1;

    HWND item = ok ? ok_button(dialog) : cancel_button(dialog);
    if (item) return press(dialog, item) ? 0 : 2;
    if (ok) return 1;  /* several buttons and none that means yes: not for a guess */
    PostMessageW(dialog, WM_COMMAND, MAKEWPARAM(IDCANCEL, BN_CLICKED), 0);
    return gone(dialog, 1500) ? 0 : 2;
}
