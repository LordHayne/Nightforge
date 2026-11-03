#!/bin/bash
# Runs the Swift test series at once, as the CI does:
#   scripts/run-tests.sh                  every tests/*Test, as many at a time as the Mac has cores
#   scripts/run-tests.sh -P 2             two at a time
#   scripts/run-tests.sh VDFTest EpicTest only these
#
# Each series writes to a log of its own in build/test-logs (or NIGHTFORGE_TEST_LOGS), and its exit code is kept beside its name
# right after it ends, so one that doesn't even build counts as failed. The logs of failed series are
# printed at the end; on GitHub every log is, each in a group of its own. Any failure: exit code 1.
# tests/CatalogProbe isn't a series: it only prints what it finds in a real Steam install.
set -euo pipefail
cd "$(dirname "$0")/.."

# One series, called by xargs below: its log, its exit code, and always 0 back, so xargs runs the rest.
if [ "${1:-}" = "--one" ]; then
  name="$(basename "$3")"
  start=$SECONDS
  rc=0
  bash "$3/run.sh" > "$2/$name.log" 2>&1 || rc=$?
  echo "$rc" > "$2/$name.rc"
  if [ "$rc" = 0 ]; then
    echo "✓ $name ($((SECONDS - start)) s)"
  else
    echo "✗ $name: exit $rc ($((SECONDS - start)) s)"
  fi
  exit 0
fi

JOBS="$(sysctl -n hw.ncpu)"
SERIES=()
while [ $# -gt 0 ]; do
  case "$1" in
    -P) JOBS="$2"; shift 2 ;;
    /*|tests/*) SERIES+=("${1%/}"); shift ;;
    *) SERIES+=("tests/${1%/}"); shift ;;
  esac
done
if [ ${#SERIES[@]} -eq 0 ]; then
  for dir in tests/*Test; do SERIES+=("$dir"); done
fi
LOGS="${NIGHTFORGE_TEST_LOGS:-build/test-logs}"
rm -rf "$LOGS" && mkdir -p "$LOGS"

echo "▸ Running ${#SERIES[@]} test series, $JOBS at a time …"
# A series xargs couldn't start has no exit code below, so it counts as failed there.
printf '%s\n' "${SERIES[@]}" | xargs -P "$JOBS" -n 1 "$PWD/scripts/run-tests.sh" --one "$LOGS" || true

FAILED=()
for dir in "${SERIES[@]}"; do
  name="$(basename "$dir")"
  # No exit code: the series never finished.
  rc="$(cat "$LOGS/$name.rc" 2>/dev/null || echo "none")"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::group::$name (exit $rc)"
    cat "$LOGS/$name.log" 2>/dev/null || true
    echo "::endgroup::"
  fi
  [ "$rc" = 0 ] || FAILED+=("$name")
done
if [ ${#FAILED[@]} -gt 0 ]; then
  for name in "${FAILED[@]}"; do
    rc="$(cat "$LOGS/$name.rc" 2>/dev/null || echo "none")"
    [ -z "${GITHUB_ACTIONS:-}" ] || echo "::error title=$name failed::exit $rc, its log follows"
    echo "──── $name: exit $rc ────"
    cat "$LOGS/$name.log" 2>/dev/null || true
  done
  echo "✗ ${#FAILED[@]} of ${#SERIES[@]} series failed: ${FAILED[*]} (logs in $LOGS)" >&2
  exit 1
fi
echo "✓ All ${#SERIES[@]} series passed (logs in $LOGS)"
