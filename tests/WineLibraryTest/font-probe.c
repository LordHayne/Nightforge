// A Windows program without a window that needs Wine's fonts: Wine's unix side loads FreeType for them with
// dlopen, the way it loads its other libraries (D3DMetal through libd3dshared). Prints how many font families
// Wine knows and the height of one. For tests/WineLibraryTest/run.sh; built with mingw-w64.
#include <windows.h>
#include <stdio.h>

static int CALLBACK count_family(const LOGFONTW *font, const TEXTMETRICW *metric, DWORD type, LPARAM count)
{
    (void)font; (void)metric; (void)type;
    ++*(int *)count;
    return 1;
}

int main(void)
{
    HDC dc = CreateCompatibleDC(NULL);
    LOGFONTW all = { .lfCharSet = DEFAULT_CHARSET };
    int families = 0;
    EnumFontFamiliesExW(dc, &all, count_family, (LPARAM)&families, 0);
    HFONT font = CreateFontW(20, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, 0, 0, L"Tahoma");
    SelectObject(dc, font);
    TEXTMETRICW metric = { 0 };
    GetTextMetricsW(dc, &metric);
    printf("families %d height %ld\n", families, (long)metric.tmHeight);
    DeleteObject(font);
    DeleteDC(dc);
    return families > 0 && metric.tmHeight > 0 ? 0 : 1;
}
