#!/bin/bash
# The order Wine gets this Mac's network interfaces in (wrapper/network-order.c, part of hide-steam-dock.dylib):
# the rules on made-up lists, then the library built as build.sh builds it, in a program like a Wine process.
# tests/NetworkOrderTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

clang -O2 -Wall -Wextra -Werror -DNIGHTFORGE_NETWORK_ORDER_TEST -I wrapper \
  -o "$WORK/rules" tests/NetworkOrderTest/rules.c wrapper/network-order.c
"$WORK/rules"

# The library as build.sh makes it, in an x86_64 program like Wine's: it needs Rosetta.
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "– this Mac's interfaces through the library: skipped, no Rosetta"
  exit 0
fi
line="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' build.sh | grep '^clang .*/hide-steam-dock.dylib')"
for source in wrapper/hide-steam-dock.m wrapper/network-order.c; do
  case "$line" in *" $source"*) ;; *) echo "✗ build.sh doesn't build $source into hide-steam-dock.dylib"; exit 1 ;; esac
done
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -framework AppKit -Wall \
  -o "$WORK/hide-steam-dock.dylib" wrapper/hide-steam-dock.m wrapper/network-order.c
clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -o "$WORK/probe" tests/NetworkOrderTest/probe.c
"$WORK/probe" > "$WORK/plain"
DYLD_INSERT_LIBRARIES="$WORK/hide-steam-dock.dylib" "$WORK/probe" > "$WORK/ordered"

# What the library should make of macOS's list: IPv4 first, then the rest but those with no address and
# either no link or switched off. The probe's columns: name ipv4 link address up.
awk '$2 == 1 {print $1}' "$WORK/plain" > "$WORK/expected"
awk '$2 == 0 && !($4 == 0 && ($3 == 0 || $5 == 0)) {print $1}' "$WORK/plain" >> "$WORK/expected"
cut -d' ' -f1 "$WORK/ordered" > "$WORK/got"
failed=0
if ! cmp -s "$WORK/expected" "$WORK/got"; then
  echo "✗ this Mac's interfaces through the library:"
  echo "  macOS:    $(cut -d' ' -f1 "$WORK/plain" | tr '\n' ' ')"
  echo "  expected: $(tr '\n' ' ' < "$WORK/expected")"
  echo "  got:      $(tr '\n' ' ' < "$WORK/got")"
  failed=1
fi
if [ "$(wc -l < "$WORK/plain")" -eq 0 ]; then
  echo "✗ macOS listed no interface at all"
  failed=1
fi
if [ $failed = 0 ]; then
  echo "✓ this Mac's $(wc -l < "$WORK/plain" | tr -d ' ') interfaces reach Wine as $(wc -l < "$WORK/got" | tr -d ' '), those with IPv4 first ($(awk '$2 == 1' "$WORK/plain" | wc -l | tr -d ' '))"
fi
exit $failed
