/*
 * Probe for docs/ENTWURF-STEAM-PAD.md, way B: do the Windows Steam's dialogs (steamwebhelper under Wine) take
 * Esc and Tab sent from inside the Wine session, without the Mac's Accessibility permission?
 *
 * On purpose it knows only Esc, Tab and Shift+Tab: no Enter, no Space, no click. Nothing it can send confirms,
 * installs, buys or changes a setting. It prints no window titles (they can name a game or the account).
 *
 * Usage: steam-keys.exe list
 *          one line per top-level window of Steam's processes, shown or not (Nightforge hides Steam's helper apps on
 *          the Mac, SteamWindow.hide): handle, process, class, size, visible, foreground
 *        steam-keys.exe key esc|tab|backtab <hwnd>     brings the window to the front, then SendInput
 *        steam-keys.exe post esc|tab|backtab <hwnd>    PostMessage to the window and its render child instead
 *        steam-keys.exe gone <hwnd> <milliseconds>     waits for the window to close or hide
 * Exit:  0 done (gone: closed), 1 gone: still open, 2 no such window, 3 not Steam's, 4 not brought to the front, 64 usage
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode -static -o steam-keys.exe steam-keys.c
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

static const wchar_t *base_name(const wchar_t *path)
{
    const wchar_t *name = path;
    for (const wchar_t *c = path; *c; ++c) {
        if (*c == L'\\' || *c == L'/') name = c + 1;
    }
    return name;
}

/* The program behind a window, by name; 0 when it can't be told. */
static int process_name(HWND window, wchar_t *name, DWORD size)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (!pid) return 0;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return 0;
    wchar_t path[MAX_PATH * 2];
    DWORD length = sizeof(path) / sizeof(path[0]);
    BOOL found = QueryFullProcessImageNameW(process, 0, path, &length);
    CloseHandle(process);
    if (!found) return 0;
    lstrcpynW(name, base_name(path), (int)size);
    return 1;
}

static int is_steams(HWND window)
{
    wchar_t name[MAX_PATH];
    if (!process_name(window, name, MAX_PATH)) return 0;
    return lstrcmpiW(name, L"steamwebhelper.exe") == 0 || lstrcmpiW(name, L"steam.exe") == 0;
}

static BOOL CALLBACK list_one(HWND window, LPARAM foreground)
{
    if (!is_steams(window)) return TRUE;
    wchar_t name[MAX_PATH] = L"?", class_name[64] = L"?";
    process_name(window, name, MAX_PATH);
    GetClassNameW(window, class_name, 64);
    RECT r;
    GetWindowRect(window, &r);
    wprintf(L"hwnd=0x%llx proc=%ls class=%ls size=%ldx%ld visible=%d foreground=%d\n", (unsigned long long)(ULONG_PTR)window,
            name, class_name, r.right - r.left, r.bottom - r.top, IsWindowVisible(window) ? 1 : 0, (HWND)foreground == window);
    return TRUE;
}

struct key { WORD vk; int shift; };

static int key_named(const wchar_t *name, struct key *key)
{
    if (lstrcmpiW(name, L"esc") == 0) { key->vk = VK_ESCAPE; key->shift = 0; return 1; }
    if (lstrcmpiW(name, L"tab") == 0) { key->vk = VK_TAB; key->shift = 0; return 1; }
    if (lstrcmpiW(name, L"backtab") == 0) { key->vk = VK_TAB; key->shift = 1; return 1; }
    return 0;  /* nothing else, Enter least of all */
}

static void add(INPUT *inputs, int *count, WORD vk, int up)
{
    ZeroMemory(&inputs[*count], sizeof(INPUT));
    inputs[*count].type = INPUT_KEYBOARD;
    inputs[*count].ki.wVk = vk;
    inputs[*count].ki.wScan = (WORD)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
    inputs[*count].ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    ++*count;
}

static int send_key(HWND window, struct key key)
{
    if (GetForegroundWindow() != window) {
        SetForegroundWindow(window);
        for (int i = 0; i < 20 && GetForegroundWindow() != window; ++i) Sleep(50);
    }
    if (GetForegroundWindow() != window) return 4;
    INPUT inputs[4];
    int count = 0;
    if (key.shift) add(inputs, &count, VK_SHIFT, 0);
    add(inputs, &count, key.vk, 0);
    add(inputs, &count, key.vk, 1);
    if (key.shift) add(inputs, &count, VK_SHIFT, 1);
    return SendInput((UINT)count, inputs, sizeof(INPUT)) == (UINT)count ? 0 : 4;
}

static BOOL CALLBACK find_render(HWND child, LPARAM result)
{
    wchar_t class_name[64];
    if (GetClassNameW(child, class_name, 64) && wcsstr(class_name, L"RenderWidgetHost")) {
        *(HWND *)result = child;
        return FALSE;
    }
    return TRUE;
}

static int post_key(HWND window, struct key key)
{
    HWND target = window;
    EnumChildWindows(window, find_render, (LPARAM)&target);
    LPARAM scan = (LPARAM)MapVirtualKeyW(key.vk, MAPVK_VK_TO_VSC) << 16;
    if (key.shift) PostMessageW(target, WM_KEYDOWN, VK_SHIFT, 1);
    PostMessageW(target, WM_KEYDOWN, key.vk, scan | 1);
    PostMessageW(target, WM_KEYUP, key.vk, scan | 1 | (1u << 30) | (1u << 31));
    if (key.shift) PostMessageW(target, WM_KEYUP, VK_SHIFT, 1 | (1u << 30) | (1u << 31));
    return 0;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc == 2 && lstrcmpiW(argv[1], L"list") == 0) {
        EnumWindows(list_one, (LPARAM)GetForegroundWindow());
        return 0;
    }
    if (argc != 4) return 64;
    if (lstrcmpiW(argv[1], L"gone") == 0) {
        HWND window = (HWND)(ULONG_PTR)wcstoull(argv[2], NULL, 16);
        DWORD limit = (DWORD)wcstoul(argv[3], NULL, 10);
        for (DWORD waited = 0; waited <= limit; waited += 100) {
            if (!IsWindow(window) || !IsWindowVisible(window)) return 0;
            Sleep(100);
        }
        return 1;
    }
    struct key key;
    if (!key_named(argv[2], &key)) return 64;
    HWND window = (HWND)(ULONG_PTR)wcstoull(argv[3], NULL, 16);
    if (!IsWindow(window)) return 2;
    if (!is_steams(window)) return 3;
    if (lstrcmpiW(argv[1], L"key") == 0) return send_key(window, key);
    if (lstrcmpiW(argv[1], L"post") == 0) return post_key(window, key);
    return 64;
}
