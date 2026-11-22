#!/bin/bash
# Probe run: own prefix in this folder, never Nightforge's; no Steam.
cd "$(dirname "$0")"
W="$HOME/Library/Application Support/Nightforge/Components/winecx/4.7.3/Libraries/Wine/bin"
export WINEPREFIX="$PWD/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
cp starter.exe child.exe prefix/drive_c/
one() {  # name, outer AVX ("" = none), command…
  local name="$1" avx="$2"; shift 2
  echo "== $name (outer ROSETTA_ADVERTISE_AVX=${avx:-none})"
  if [ -n "$avx" ]; then env ROSETTA_ADVERTISE_AVX="$avx" "$W/wine64" "$@" > out.txt 2>&1 &
  else env -u ROSETTA_ADVERTISE_AVX "$W/wine64" "$@" > out.txt 2>&1 & fi
  local launcher=$!
  local pid=""
  for _ in $(seq 1 40); do
    pid=$(ps -axo pid=,command= | awk '/[c]hild\.exe/ && !/starter/ {print $1; exit}')
    [ -n "$pid" ] && break
    sleep 0.1
  done
  if [ -n "$pid" ]; then ./procenv "$pid" NF_PROBE ROSETTA_ADVERTISE_AVX; else echo "unix: child not found"; fi
  wait $launcher; echo "exit $?"
  cat out.txt | tr -d '\r'
}
one control-without "" 'C:\child.exe'
one control-with 1 'C:\child.exe'
one starter-sets "" 'C:\starter.exe' set 'C:\child.exe'
one starter-unsets 1 'C:\starter.exe' unset 'C:\child.exe'
one starter-keeps 1 'C:\starter.exe' keep 'C:\child.exe'
"$W/wineserver" -k
