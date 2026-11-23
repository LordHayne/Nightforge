// Prints what if_nameindex() gives this program, one interface per line with what macOS says of it:
// "name ipv4 link address up" (link: 1, 0, -1 unknown). Run with and without hide-steam-dock.dylib by
// tests/NetworkOrderTest/run.sh. x86_64, like the Wine processes the library goes into. An argument becomes the
// program's name (argv[0]) first, as Wine sets it to the Windows path: the library orders only in winedevice.exe.
#include <crt_externs.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_media.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    if (argc > 1) (*_NSGetArgv())[0] = argv[1];
    struct if_nameindex *list = if_nameindex(), *entry;
    struct ifaddrs *addresses = NULL, *a;
    int sock = socket(AF_INET, SOCK_DGRAM, 0);

    if (!list || getifaddrs(&addresses) != 0) return 2;
    for (entry = list; entry->if_index; entry++) {
        struct ifmediareq request;
        struct ifreq flags;
        int ipv4 = 0, address = 0, link = -1, up = 1;

        for (a = addresses; a; a = a->ifa_next) {
            if (!a->ifa_addr || strcmp(a->ifa_name, entry->if_name)) continue;
            if (a->ifa_addr->sa_family == AF_INET) ipv4 = address = 1;
            if (a->ifa_addr->sa_family == AF_INET6) address = 1;
        }
        memset(&request, 0, sizeof(request));
        strlcpy(request.ifm_name, entry->if_name, sizeof(request.ifm_name));
        if (sock >= 0 && ioctl(sock, SIOCGIFMEDIA, &request) == 0 && (request.ifm_status & IFM_AVALID))
            link = (request.ifm_status & IFM_ACTIVE) ? 1 : 0;
        memset(&flags, 0, sizeof(flags));
        strlcpy(flags.ifr_name, entry->if_name, sizeof(flags.ifr_name));
        if (sock >= 0 && ioctl(sock, SIOCGIFFLAGS, &flags) == 0) up = (flags.ifr_flags & IFF_UP) ? 1 : 0;
        printf("%s %d %d %d %d\n", entry->if_name, ipv4, link, address, up);
    }
    if_freenameindex(list);
    freeifaddrs(addresses);
    if (sock >= 0) close(sock);
    return 0;
}
