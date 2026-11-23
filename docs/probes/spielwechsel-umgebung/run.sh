#!/bin/bash
# Probe run: an own prefix in the folder given ($1, default: beside this script), never Nightforge's; no Steam, no game.
#   run.sh <work folder with spawn-env.dylib, starter.exe, child.exe>
set -u
cd "${1:-$(dirname "$0")}" || exit 1
W="$HOME/Library/Application Support/Nightforge/Components/winecx/4.7.3/Libraries/Wine/bin"
export WINEPREFIX="$PWD/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" WINEMSYNC=0
mkdir -p prefix
[ -d prefix/drive_c ] || "$W/wine64" wineboot -i > /dev/null 2>&1
cp starter.exe child.exe prefix/drive_c/
one() {  # name, outer AVX ("" = none), dylib (0/1), NF_SPAWN_AVX
  local name="$1" avx="$2" lib="$3" want="$4"
  echo "== $name (outer AVX=${avx:-none}, interposer=$lib, NF_SPAWN_AVX=${want:-none})"
  local env=(env -u ROSETTA_ADVERTISE_AVX -u DYLD_INSERT_LIBRARIES)
  [ -n "$avx" ] && env+=(ROSETTA_ADVERTISE_AVX="$avx")
  [ "$lib" = 1 ] && env+=(DYLD_INSERT_LIBRARIES="$PWD/spawn-env.dylib" NF_SPAWN_MATCH=child.exe NF_SPAWN_AVX="$want")
  "${env[@]}" "$W/wine64" 'C:\starter.exe' keep 'C:\child.exe' > out.txt 2> err.txt
  echo "exit $?"
  tr -d '\r' < out.txt
  grep -h "spawn-env:" err.txt | sed -E 's#/Users/[^ ]*/#~/#' | sort | uniq -c
}
one control-avx 1 0 ""
one control-none "" 0 ""
one spawn-removes 1 1 0
one spawn-adds "" 1 1
"$W/wineserver" -k
