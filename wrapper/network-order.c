// Wine's list of network adapters, in an order Steam's sign-in finds the connected one in.
//
// Wine shows Windows programs every network interface macOS has (nsiproxy.sys asks if_nameindex()), in
// macOS's order, and calls each one that's switched on "up" – on macOS it doesn't look at the link. A
// MacBook Pro with M5 Pro has 23 of them: its Thunderbolt ports bring anpi0–2, en1–en6 and bridge0, all
// on and none with a cable in, and the Wi-Fi, en0, comes 14th. Steam's sign-in waits for a connected
// network device among the first ten it lists (steamui.dll asks IClientNetworkDeviceManager for ten;
// steamclient64.dll calls one "Connecting" when it's up without an IPv4 address, "Connected" with one).
// It never got to en0 and went on after 20 s: "Timed out waiting for network" at every Steam start
// (22.11.2026, F4 in docs/TODO.md). The M5 MacBook Pro before it has fewer ports; en0 made the ten.
//
// So Wine gets the list
// - with the interfaces that have an IPv4 address first, in macOS's order otherwise;
// - without those that have no address and either no link (`ifconfig`: "status: inactive") or are
//   switched off (gif0, stf0, ap1, nan0). One with an address stays, so Wine never meets an address on
//   an interface it doesn't know. One that gets a cable later is in the list the next time Wine asks.
//   Wine adds what's new at the end of its own list and never reorders it: a Wi-Fi that joins only after
//   Wine first looked (right after logging in) comes last, and the list it comes after is short.
// Loaded into every Wine process as a part of hide-steam-dock.dylib (DYLD_INSERT_LIBRARIES, DockHider.swift).
//
// Build: in hide-steam-dock.dylib (build.sh). tests/NetworkOrderTest compiles it with NIGHTFORGE_NETWORK_ORDER_TEST.

#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_media.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#include "network-order.h"

int nightforge_interface_place(int link, int up, int ipv4, int address)
{
    if (ipv4) return NIGHTFORGE_INTERFACE_FIRST;
    if (!address && (link == 0 || !up)) return NIGHTFORGE_INTERFACE_LEFT_OUT;
    return NIGHTFORGE_INTERFACE_LATER;
}

void nightforge_arrange_interfaces(struct if_nameindex *list, int (*place)(const char *name, void *context), void *context)
{
    size_t count = 0, kept = 0, i;
    struct if_nameindex *sorted;
    int *places;

    while (list[count].if_index) count++;
    if (!count) return;
    sorted = malloc(count * sizeof(*sorted));
    places = malloc(count * sizeof(*places));
    if (!sorted || !places) {
        free(sorted);
        free(places);
        return;
    }
    for (i = 0; i < count; i++) places[i] = place(list[i].if_name, context);
    for (i = 0; i < count; i++)
        if (places[i] == NIGHTFORGE_INTERFACE_FIRST) sorted[kept++] = list[i];
    for (i = 0; i < count; i++)
        if (places[i] == NIGHTFORGE_INTERFACE_LATER) sorted[kept++] = list[i];
    // The names stay where they are: if_nameindex() hands out one block, entries and names together,
    // and if_freenameindex() frees just that.
    memcpy(list, sorted, kept * sizeof(*sorted));
    list[kept].if_index = 0;
    list[kept].if_name = NULL;
    free(sorted);
    free(places);
}

#ifndef NIGHTFORGE_NETWORK_ORDER_TEST

struct facts {
    struct ifaddrs *addresses;
    int sock;
};

// 1 with a link, 0 without, -1 when macOS doesn't say (lo0, utun…, or no answer).
static int link_state(int sock, const char *name)
{
    struct ifmediareq request;

    if (sock < 0) return -1;
    memset(&request, 0, sizeof(request));
    strlcpy(request.ifm_name, name, sizeof(request.ifm_name));
    if (ioctl(sock, SIOCGIFMEDIA, &request) < 0 || !(request.ifm_status & IFM_AVALID)) return -1;
    return (request.ifm_status & IFM_ACTIVE) ? 1 : 0;
}

// Whether it's switched on; when macOS doesn't answer, it counts as on, as it does for Wine.
static int switched_on(int sock, const char *name)
{
    struct ifreq request;

    if (sock < 0) return 1;
    memset(&request, 0, sizeof(request));
    strlcpy(request.ifr_name, name, sizeof(request.ifr_name));
    if (ioctl(sock, SIOCGIFFLAGS, &request) < 0) return 1;
    return (request.ifr_flags & IFF_UP) ? 1 : 0;
}

static int place_of(const char *name, void *context)
{
    struct facts *facts = context;
    struct ifaddrs *entry;
    int ipv4 = 0, address = 0;

    for (entry = facts->addresses; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || strcmp(entry->ifa_name, name)) continue;
        if (entry->ifa_addr->sa_family == AF_INET) ipv4 = address = 1;
        if (entry->ifa_addr->sa_family == AF_INET6) address = 1;
    }
    return nightforge_interface_place(link_state(facts->sock, name), switched_on(facts->sock, name), ipv4, address);
}

static struct if_nameindex *nightforge_if_nameindex(void)
{
    // The real one: a library's interposing doesn't reach its own calls.
    struct if_nameindex *list = if_nameindex();
    struct facts facts = { NULL, -1 };
    int saved = errno;

    // Without the addresses nothing is known for sure: macOS's list as it is.
    if (!list || getifaddrs(&facts.addresses) != 0) return list;
    facts.sock = socket(AF_INET, SOCK_DGRAM, 0);
    nightforge_arrange_interfaces(list, place_of, &facts);
    if (facts.sock >= 0) close(facts.sock);
    freeifaddrs(facts.addresses);
    errno = saved;
    return list;
}

__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} interpose_if_nameindex __attribute__((section("__DATA,__interpose"))) = {
    (const void *)nightforge_if_nameindex, (const void *)if_nameindex
};

#endif
