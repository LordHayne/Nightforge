#!/bin/bash
# Probe: does IsProcessorFeaturePresent(AVX) depend on how the Wine session began (its first process's environment)?
# Own prefix in the work folder given ($1), never Nightforge's; no Steam, no game. Each case begins a fresh session.
#   run.sh <work folder with child.exe>
set -u
cd "${1:?work folder}" || exit 1
W="$HOME/Library/Application Support/Nightforge/Components/winecx/4.7.3/Libraries/Wine/bin"
export WINEPREFIX="$PWD/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" WINEMSYNC=0
mkdir -p prefix
[ -d prefix/drive_c ] || env -u ROSETTA_ADVERTISE_AVX "$W/wine64" wineboot -i > /dev/null 2>&1
cp child.exe prefix/drive_c/
"$W/wineserver" -k 2>/dev/null; "$W/wineserver" -w 2>/dev/null
child() {  # label, AVX for the child ("" = none)
  echo "-- $1 (child AVX=${2:-none})"
  if [ -n "$2" ]; then env ROSETTA_ADVERTISE_AVX="$2" "$W/wine64" 'C:\child.exe'; else env -u ROSETTA_ADVERTISE_AVX "$W/wine64" 'C:\child.exe'; fi \
    2>/dev/null | tr -d '\r' | grep -E "cpuid|IsProcessor"
}
fresh() {  # a session begun by a first process with AVX ($1) that stays up while the children run
  "$W/wineserver" -k 2>/dev/null; "$W/wineserver" -w 2>/dev/null
  echo "== session begun with AVX=${1:-none}"
  if [ -n "$1" ]; then env ROSETTA_ADVERTISE_AVX="$1" "$W/wine64" cmd /c "ping -n 20 127.0.0.1 >nul" > /dev/null 2>&1 &
  else env -u ROSETTA_ADVERTISE_AVX "$W/wine64" cmd /c "ping -n 20 127.0.0.1 >nul" > /dev/null 2>&1 & fi
  sleep 4
}
fresh 1;  child "same session" 1; child "same session" ""
fresh "";  child "same session" 1; child "same session" ""
"$W/wineserver" -k 2>/dev/null
echo "== no session before: the child begins it"
child "first process" 1
"$W/wineserver" -k 2>/dev/null; "$W/wineserver" -w 2>/dev/null
child "first process" ""
"$W/wineserver" -k 2>/dev/null
