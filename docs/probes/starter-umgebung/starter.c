// Probe (claude/spielwechsel-035): does a variable a Windows program sets under Wine reach its child – on the Windows
// side, in the child's Unix environment, and for Rosetta (AVX)? Not part of Nightforge.
// starter.exe <set|unset|keep> <child command line…>
#include <windows.h>
#include <stdio.h>
#include <string.h>

int wmain(int argc, wchar_t **argv) {
    if (argc < 3) { fwprintf(stderr, L"usage: starter set|unset|keep child...\n"); return 2; }
    SetEnvironmentVariableW(L"NF_PROBE", L"from-the-starter");
    if (!wcscmp(argv[1], L"set")) SetEnvironmentVariableW(L"ROSETTA_ADVERTISE_AVX", L"1");
    else if (!wcscmp(argv[1], L"unset")) SetEnvironmentVariableW(L"ROSETTA_ADVERTISE_AVX", NULL);
    // The rest of the command line, as Steam's %command% would hand it over.
    wchar_t *line = GetCommandLineW();
    wchar_t *rest = wcsstr(line, argv[2]);
    if (rest > line && rest[-1] == L'"') rest--;
    STARTUPINFOW si = { sizeof si };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(NULL, rest, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        fwprintf(stderr, L"CreateProcess failed: %lu\n", GetLastError());
        return 3;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}
