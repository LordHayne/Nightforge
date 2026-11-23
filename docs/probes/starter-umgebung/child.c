// Probe child: what it sees of the variables, and whether the CPU it runs on says AVX (Rosetta's answer).
#include <windows.h>
#include <stdio.h>
#include <cpuid.h>

int main(void) {
    char value[256];
    DWORD n = GetEnvironmentVariableA("NF_PROBE", value, sizeof value);
    printf("windows NF_PROBE=%s\n", n ? value : "(none)");
    n = GetEnvironmentVariableA("ROSETTA_ADVERTISE_AVX", value, sizeof value);
    printf("windows ROSETTA_ADVERTISE_AVX=%s\n", n ? value : "(none)");
    unsigned a, b, c, d;
    __get_cpuid(1, &a, &b, &c, &d);
    printf("cpuid avx=%u osxsave=%u\n", (c >> 28) & 1, (c >> 27) & 1);
    printf("IsProcessorFeaturePresent(AVX)=%d\n", IsProcessorFeaturePresent(39));
    fflush(stdout);
    Sleep(4000);  // time for the Unix side to be read
    return 7;
}
