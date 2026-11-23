// Wine's list of network adapters, in an order Steam's sign-in finds the connected one in (network-order.c).
#ifndef NIGHTFORGE_NETWORK_ORDER_H
#define NIGHTFORGE_NETWORK_ORDER_H

#include <net/if.h>

enum {
    NIGHTFORGE_INTERFACE_LEFT_OUT = 0,
    NIGHTFORGE_INTERFACE_FIRST = 1,
    NIGHTFORGE_INTERFACE_LATER = 2,
};

// Where an interface goes. `link`: 1 with a link, 0 without, -1 when macOS doesn't say; `up`: whether
// it's switched on; `ipv4` and `address`: whether it has an IPv4 address, and any address at all.
int nightforge_interface_place(int link, int up, int ipv4, int address);

// Puts `list` (if_nameindex()'s, ended by an entry with index 0) in order where it is: the FIRST
// entries, then the LATER ones, each in the order they came; LEFT_OUT ones are taken out.
void nightforge_arrange_interfaces(struct if_nameindex *list, int (*place)(const char *name, void *context), void *context);

// Whether a process orders the list at all: only Wine's device host, `program` (argv[0], which Wine sets to the
// Windows path) naming winedevice.exe, case and slashes aside. Every other process – Steam, a game, a game with an
// anti-cheat – gets macOS's list unchanged.
int nightforge_orders_interfaces(const char *program);

#endif
