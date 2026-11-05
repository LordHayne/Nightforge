/* A Direct3D 9 program that proves a device draws: it creates a HAL device on a window, clears it
 * blue, draws a red triangle in the middle, reads the picture back and checks both colours, then
 * presents frames for two seconds (or as many as the first argument says: Nightforge's Vulkan layer
 * logs the frame rate after ten). Prints which d3d9.dll answered (Wine's own or a native one such
 * as DXVK's) and the adapter it reports. Exit code 0 only when the picture is right.
 *
 *   i686-w64-mingw32-gcc -O2 -o d3d9probe32.exe d3d9probe.c -ld3d9 -lgdi32
 *   x86_64-w64-mingw32-gcc -O2 -o d3d9probe64.exe d3d9probe.c -ld3d9 -lgdi32
 */
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZE 256

struct vertex { float x, y, z, rhw; DWORD colour; };

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM w, LPARAM l)
{
    return DefWindowProcA(window, message, w, l);
}

static int near_colour(DWORD pixel, DWORD wanted)
{
    for (int shift = 0; shift < 24; shift += 8) {
        int a = (pixel >> shift) & 0xff, b = (wanted >> shift) & 0xff;
        if (a - b > 8 || b - a > 8) return 0;
    }
    return 1;
}

static void draw(IDirect3DDevice9 *device)
{
    struct vertex triangle[3] = {
        { SIZE / 2.0f, SIZE / 4.0f, 0.5f, 1.0f, 0xffff0000 },
        { SIZE * 3 / 4.0f, SIZE * 3 / 4.0f, 0.5f, 1.0f, 0xffff0000 },
        { SIZE / 4.0f, SIZE * 3 / 4.0f, 0.5f, 1.0f, 0xffff0000 },
    };
    IDirect3DDevice9_Clear(device, 0, NULL, D3DCLEAR_TARGET, 0xff0000ff, 1.0f, 0);
    IDirect3DDevice9_BeginScene(device);
    IDirect3DDevice9_SetFVF(device, D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
    IDirect3DDevice9_SetRenderState(device, D3DRS_LIGHTING, FALSE);
    IDirect3DDevice9_SetRenderState(device, D3DRS_CULLMODE, D3DCULL_NONE);
    IDirect3DDevice9_DrawPrimitiveUP(device, D3DPT_TRIANGLELIST, 1, triangle, sizeof(triangle[0]));
    IDirect3DDevice9_EndScene(device);
}

int main(int argc, char **argv)
{
    int duration = argc > 1 ? atoi(argv[1]) : 2;
    if (duration < 1) duration = 2;
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("D3D9PROBE %d-bit\n", (int)sizeof(void *) * 8);

    WNDCLASSA class = { 0 };
    class.lpfnWndProc = window_proc;
    class.hInstance = GetModuleHandleA(NULL);
    class.lpszClassName = "d3d9probe";
    RegisterClassA(&class);
    RECT rect = { 0, 0, SIZE, SIZE };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);
    HWND window = CreateWindowA("d3d9probe", "Nightforge D3D9 probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                                100, 100, rect.right - rect.left, rect.bottom - rect.top, NULL, NULL, class.hInstance, NULL);

    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    HMODULE module = GetModuleHandleA("d3d9.dll");
    char path[MAX_PATH] = "?";
    if (module) GetModuleFileNameA(module, path, sizeof(path));
    /* Wine marks its own PE libraries in the DOS stub. */
    int builtin = module && !memcmp((const char *)module + 0x40, "Wine builtin DLL", 16);
    printf("d3d9.dll: %s (%s)\n", path, builtin ? "Wine builtin" : "native");
    if (!d3d) { printf("D3D9PROBE FAIL Direct3DCreate9\n"); return 2; }

    D3DADAPTER_IDENTIFIER9 id;
    if (SUCCEEDED(IDirect3D9_GetAdapterIdentifier(d3d, D3DADAPTER_DEFAULT, 0, &id)))
        printf("adapter: %s (vendor %04lx, device %04lx, driver %s)\n", id.Description,
               (unsigned long)id.VendorId, (unsigned long)id.DeviceId, id.Driver);

    D3DPRESENT_PARAMETERS parameters = { 0 };
    parameters.BackBufferWidth = SIZE;
    parameters.BackBufferHeight = SIZE;
    parameters.BackBufferFormat = D3DFMT_X8R8G8B8;
    parameters.BackBufferCount = 1;
    parameters.SwapEffect = D3DSWAPEFFECT_DISCARD;
    parameters.hDeviceWindow = window;
    parameters.Windowed = TRUE;
    parameters.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    IDirect3DDevice9 *device = NULL;
    HRESULT result = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window,
                                             D3DCREATE_HARDWARE_VERTEXPROCESSING, &parameters, &device);
    printf("CreateDevice: 0x%08lx\n", (unsigned long)result);
    if (FAILED(result)) { printf("D3D9PROBE FAIL CreateDevice\n"); return 3; }

    D3DCAPS9 caps;
    IDirect3DDevice9_GetDeviceCaps(device, &caps);
    printf("caps: vertex shader %lu.%lu, pixel shader %lu.%lu\n",
           (unsigned long)D3DSHADER_VERSION_MAJOR(caps.VertexShaderVersion), (unsigned long)D3DSHADER_VERSION_MINOR(caps.VertexShaderVersion),
           (unsigned long)D3DSHADER_VERSION_MAJOR(caps.PixelShaderVersion), (unsigned long)D3DSHADER_VERSION_MINOR(caps.PixelShaderVersion));

    draw(device);
    IDirect3DSurface9 *target = NULL, *copy = NULL;
    IDirect3DDevice9_GetRenderTarget(device, 0, &target);
    IDirect3DDevice9_CreateOffscreenPlainSurface(device, SIZE, SIZE, D3DFMT_X8R8G8B8, D3DPOOL_SYSTEMMEM, &copy, NULL);
    result = IDirect3DDevice9_GetRenderTargetData(device, target, copy);
    D3DLOCKED_RECT locked;
    int ok = 0;
    if (SUCCEEDED(result) && SUCCEEDED(IDirect3DSurface9_LockRect(copy, &locked, NULL, D3DLOCK_READONLY))) {
        DWORD middle = ((DWORD *)((BYTE *)locked.pBits + locked.Pitch * (SIZE * 5 / 8)))[SIZE / 2] & 0xffffff;
        DWORD corner = ((DWORD *)((BYTE *)locked.pBits + locked.Pitch * 4))[4] & 0xffffff;
        IDirect3DSurface9_UnlockRect(copy);
        ok = near_colour(middle, 0xff0000) && near_colour(corner, 0x0000ff);
        printf("pixels: middle %06lx (red wanted), corner %06lx (blue wanted)\n", (unsigned long)middle, (unsigned long)corner);
    } else {
        printf("readback: 0x%08lx\n", (unsigned long)result);
    }

    /* Frames for `duration` seconds: the swapchain presents, and a rough rate. */
    LARGE_INTEGER frequency, start, now;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&start);
    int frames = 0;
    HRESULT presented = D3D_OK;
    do {
        MSG message;
        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&message);
        draw(device);
        presented = IDirect3DDevice9_Present(device, NULL, NULL, NULL, NULL);
        frames++;
        QueryPerformanceCounter(&now);
    } while (SUCCEEDED(presented) && now.QuadPart - start.QuadPart < duration * frequency.QuadPart);
    double seconds = (double)(now.QuadPart - start.QuadPart) / frequency.QuadPart;
    printf("present: 0x%08lx, %d frames in %.1f s (%.0f per second)\n", (unsigned long)presented, frames, seconds, frames / seconds);

    if (copy) IDirect3DSurface9_Release(copy);
    if (target) IDirect3DSurface9_Release(target);
    IDirect3DDevice9_Release(device);
    IDirect3D9_Release(d3d);
    DestroyWindow(window);
    ok = ok && SUCCEEDED(presented);
    printf("D3D9PROBE %s\n", ok ? "OK" : "FAIL picture");
    return ok ? 0 : 4;
}
