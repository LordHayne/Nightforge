/*
 * A stand-in for Unity's configuration window (tests/UnityDialogTest/dialog.sh): a dialog like
 * Unity's – "Play!", "Quit", a "Windowed" box, a list – with the title it's given. It writes what
 * ended it into a file: "play", "quit" or "timeout".
 *
 * Usage: stand-in.exe <title> <result file> <seconds>
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>

#define TIMEOUT 3

static const wchar_t *title;
static UINT seconds;

static INT_PTR CALLBACK dialog(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    (void)lparam;
    switch (message) {
    case WM_INITDIALOG:
        SetWindowTextW(window, title);
        SetTimer(window, 1, seconds * 1000, NULL);
        SendDlgItemMessageW(window, 100, CB_ADDSTRING, 0, (LPARAM)L"1920 x 1080");
        SendDlgItemMessageW(window, 100, CB_SETCURSEL, 0, 0);
        return TRUE;
    case WM_COMMAND:
        if (LOWORD(wparam) == IDOK || LOWORD(wparam) == IDCANCEL) {
            EndDialog(window, LOWORD(wparam));
            return TRUE;
        }
        return FALSE;
    case WM_TIMER:
        EndDialog(window, TIMEOUT);
        return TRUE;
    }
    return FALSE;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR cmdline, int show)
{
    (void)previous; (void)cmdline; (void)show;
    int count = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!argv || count != 4) return 64;
    title = argv[1];
    seconds = (UINT)_wtoi(argv[3]);

    INT_PTR result = DialogBoxW(instance, MAKEINTRESOURCEW(1), NULL, dialog);
    const char *word = result == IDOK ? "play" : result == IDCANCEL ? "quit" : "timeout";
    HANDLE file = CreateFileW(argv[2], GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 1;
    DWORD written;
    WriteFile(file, word, (DWORD)strlen(word), &written, NULL);
    CloseHandle(file);
    return 0;
}
