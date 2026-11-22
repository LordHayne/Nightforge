// The rules of wrapper/network-order.c, on made-up lists: tests/NetworkOrderTest/run.sh
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "network-order.h"

static int failures;

static void check(int condition, const char *message)
{
    if (!condition) {
        failures++;
        printf("✗ %s\n", message);
    }
}

// An interface as the test sees it: name, link (1, 0, -1 unknown), switched on, IPv4, any address.
struct fake {
    const char *name;
    int link, up, ipv4, address;
};

static struct fake *fakes;

static int fake_place(const char *name, void *context)
{
    (void)context;
    for (struct fake *f = fakes; f->name; f++)
        if (!strcmp(f->name, name)) return nightforge_interface_place(f->link, f->up, f->ipv4, f->address);
    return NIGHTFORGE_INTERFACE_LATER;
}

// The names after arranging, joined by spaces – from a block laid out like if_nameindex()'s.
static void arranged(struct fake *list, char *out, size_t size)
{
    size_t count = 0, i;
    struct if_nameindex *block;

    while (list[count].name) count++;
    block = calloc(count + 1, sizeof(*block));
    for (i = 0; i < count; i++) {
        block[i].if_index = (unsigned)(i + 1);
        block[i].if_name = (char *)list[i].name;
    }
    fakes = list;
    nightforge_arrange_interfaces(block, fake_place, NULL);
    out[0] = 0;
    for (i = 0; block[i].if_index; i++) {
        if (i) strlcat(out, " ", size);
        strlcat(out, block[i].if_name, size);
    }
    check(block[i].if_name == NULL, "the list ends as if_nameindex()'s does");
    free(block);
}

int main(void)
{
    char out[1024];

    check(nightforge_interface_place(-1, 1, 1, 1) == NIGHTFORGE_INTERFACE_FIRST, "an interface with IPv4 comes first");
    check(nightforge_interface_place(1, 1, 1, 1) == NIGHTFORGE_INTERFACE_FIRST, "… with a link too");
    check(nightforge_interface_place(0, 1, 0, 0) == NIGHTFORGE_INTERFACE_LEFT_OUT, "on, but no link and no address: left out");
    check(nightforge_interface_place(-1, 0, 0, 0) == NIGHTFORGE_INTERFACE_LEFT_OUT, "switched off and no address (gif0, ap1): left out");
    check(nightforge_interface_place(0, 1, 0, 1) == NIGHTFORGE_INTERFACE_LATER, "no link but an address (IPv6): stays, Wine must know it");
    check(nightforge_interface_place(-1, 0, 0, 1) == NIGHTFORGE_INTERFACE_LATER, "switched off with an address: stays too");
    check(nightforge_interface_place(-1, 1, 0, 0) == NIGHTFORGE_INTERFACE_LATER, "on, and macOS doesn't say more (utun, llw0): stays");
    check(nightforge_interface_place(1, 1, 0, 0) == NIGHTFORGE_INTERFACE_LATER, "a link but no address yet (DHCP): stays");

    // The MacBook Pro M5 Pro on 22.11.2026, as macOS lists it: en0 was 14th, after ten without a cable.
    struct fake m5pro[] = {
        { "lo0", -1, 1, 1, 1 }, { "gif0", -1, 0, 0, 0 }, { "stf0", -1, 0, 0, 0 },
        { "anpi1", 0, 1, 0, 0 }, { "anpi0", 0, 1, 0, 0 }, { "anpi2", 0, 1, 0, 0 },
        { "en3", 0, 1, 0, 0 }, { "en4", 0, 1, 0, 0 }, { "en5", 0, 1, 0, 0 }, { "en1", 0, 1, 0, 0 }, { "en6", 0, 1, 0, 0 },
        { "en2", 0, 1, 0, 0 }, { "bridge0", 0, 1, 0, 0 }, { "ap1", -1, 0, 0, 0 }, { "en0", 1, 1, 1, 1 },
        { "utun0", -1, 1, 0, 1 }, { "awdl0", 1, 1, 0, 1 }, { "llw0", -1, 1, 0, 1 }, { "utun1", -1, 1, 0, 1 },
        { "nan0", -1, 0, 0, 0 }, { "utun2", -1, 1, 0, 1 }, { "utun3", -1, 1, 0, 1 }, { "utun4", -1, 1, 0, 1 },
        { "utun5", -1, 1, 0, 1 }, { NULL, 0, 0, 0, 0 },
    };
    arranged(m5pro, out, sizeof(out));
    check(!strcmp(out, "lo0 en0 utun0 awdl0 llw0 utun1 utun2 utun3 utun4 utun5"), out);
    check(!strncmp(out, "lo0 en0 ", 8), "the Wi-Fi comes right after the loopback, which Steam skips");

    // The same Mac right after logging in, the Wi-Fi not joined yet when Wine first looks: Wine adds en0 at
    // the end of its list once it has joined, and Steam counts the first ten after the loopback.
    m5pro[14] = (struct fake){ "en0", 0, 1, 0, 0 };
    arranged(m5pro, out, sizeof(out));
    check(!strcmp(out, "lo0 utun0 awdl0 llw0 utun1 utun2 utun3 utun4 utun5"), out);
    {
        int before = 0;
        for (const char *c = out; *c; c++) before += *c == ' ';
        check(before + 1 <= 10, "a Wi-Fi joining later still comes among Steam's ten");
    }

    // A dock's Ethernet with the cable in, Wi-Fi off and a VPN on: the Ethernet still comes first.
    struct fake dock[] = {
        { "lo0", -1, 1, 1, 1 }, { "en0", 0, 1, 0, 0 }, { "utun0", -1, 1, 0, 1 }, { "utun1", -1, 1, 0, 1 },
        { "utun2", -1, 1, 0, 1 }, { "utun3", -1, 1, 0, 1 }, { "utun4", -1, 1, 1, 1 }, { "llw0", -1, 1, 0, 1 },
        { "en8", 1, 1, 1, 1 }, { NULL, 0, 0, 0, 0 },
    };
    arranged(dock, out, sizeof(out));
    check(!strcmp(out, "lo0 utun4 en8 utun0 utun1 utun2 utun3 llw0"), out);

    // A Thunderbolt bridge with a self-assigned IPv6 address but no cable stays where it was.
    struct fake bridge[] = {
        { "lo0", -1, 1, 1, 1 }, { "bridge0", 0, 1, 0, 1 }, { "en1", 0, 1, 0, 0 }, { "en0", 1, 1, 1, 1 }, { NULL, 0, 0, 0, 0 },
    };
    arranged(bridge, out, sizeof(out));
    check(!strcmp(out, "lo0 en0 bridge0"), out);

    // Nothing known for sure: every interface stays, in macOS's order.
    struct fake unknown[] = { { "lo0", -1, 1, 0, 0 }, { "en0", -1, 1, 0, 0 }, { "en1", -1, 1, 0, 0 }, { NULL, 0, 0, 0, 0 } };
    arranged(unknown, out, sizeof(out));
    check(!strcmp(out, "lo0 en0 en1"), out);

    // An empty list stays empty.
    struct fake none[] = { { NULL, 0, 0, 0, 0 } };
    arranged(none, out, sizeof(out));
    check(!strcmp(out, ""), "an empty list stays empty");

    // Only Wine's device host orders the list (docs/AUDIT-0.3.5.md, M1): nothing changes in a game's process.
    check(nightforge_orders_interfaces("C:\\windows\\system32\\winedevice.exe"), "winedevice.exe, as Wine names it: ordered");
    check(nightforge_orders_interfaces("c:\\WINDOWS\\SYSTEM32\\WineDevice.EXE"), "case doesn't count");
    check(nightforge_orders_interfaces("/x/system32/winedevice.exe") && nightforge_orders_interfaces("winedevice.exe"),
          "a slash, or the name alone");
    check(!nightforge_orders_interfaces("C:\\Program Files (x86)\\Steam\\steam.exe"), "Steam: macOS's list unchanged");
    check(!nightforge_orders_interfaces("C:\\Program Files (x86)\\Overwatch\\_retail_\\Overwatch.exe"),
          "a game with an anti-cheat: unchanged");
    check(!nightforge_orders_interfaces("C:\\games\\notwinedevice.exe") && !nightforge_orders_interfaces("C:\\x\\winedevice.exe.bak")
          && !nightforge_orders_interfaces("C:\\x\\winedevice.ex"), "only that file name, whole");
    check(!nightforge_orders_interfaces(NULL) && !nightforge_orders_interfaces(""), "no name: unchanged");

    printf(failures ? "%d failed\n" : "✓ the order Wine gets the network interfaces in\n", failures);
    return failures ? 1 : 0;
}
