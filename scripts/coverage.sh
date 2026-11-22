#!/bin/bash
# Measures how much of Sources/Nightforge the tests run, per file:
#   scripts/coverage.sh                    every tests/*Test, four at a time
#   scripts/coverage.sh VDFTest EpicTest   only these
#   scripts/coverage.sh -P 2               two at a time
#   scripts/coverage.sh --html             also an annotated copy of every file in build/coverage/html
#   scripts/coverage.sh --files            … as text in build/coverage/files, where `grep -n '^ *[0-9]*| *0|'`
#                                          finds the lines no test ran, and `^0` marks parts of a line
#
# The tests' own run.sh files stay as they are: a swiftc in front of the real one on PATH adds the
# coverage flags and keeps a copy of each test binary (some run.sh files delete theirs at the end).
# The app is compiled once with those flags (scripts/testbuild/swiftc), as in scripts/run-tests.sh.
# The table lands in build/coverage/report.txt, with what failed in build/coverage/logs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk

HTML=0
FILES=0
JOBS=4
TESTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --html) HTML=1 ;;
    --files) FILES=1 ;;
    -P) JOBS="$2"; shift ;;
    *) TESTS+=("tests/${1#tests/}") ;;
  esac
  shift
done
if [ ${#TESTS[@]} -eq 0 ]; then
  for dir in tests/*Test; do TESTS+=("$dir"); done
fi

OUT="$ROOT/build/coverage"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT" && mkdir -p "$OUT/logs" "$WORK/bin" "$WORK/objects" "$WORK/profiles"

REAL_SWIFTC="$(xcrun -f swiftc)"
# shellcheck source=testbuild/compile-once.sh
. scripts/testbuild/compile-once.sh
compile_app_once "$JOBS" -profile-generate -profile-coverage-mapping
if [ -n "${NIGHTFORGE_TEST_OBJECTS:-}" ]; then REAL_SWIFTC="$ROOT/scripts/testbuild/swiftc"; fi
cat > "$WORK/bin/swiftc" <<EOF
#!/bin/bash
# Compiles with coverage and keeps the binary for llvm-cov.
set -e
output=""
previous=""
for arg in "\$@"; do
  [ "\$previous" = "-o" ] && output="\$arg"
  previous="\$arg"
done
"$REAL_SWIFTC" -profile-generate -profile-coverage-mapping "\$@"
if [ -n "\$output" ] && [ -f "\$output" ]; then
  cp "\$output" "\$(mktemp "$WORK/objects/\${NIGHTFORGE_COVERAGE_TEST}.XXXX")"
fi
EOF
chmod +x "$WORK/bin/swiftc"

# One test: its profile files are named after it, so four running at once never share one.
cat > "$WORK/run-one.sh" <<EOF
#!/bin/bash
name="\$(basename "\$1")"
export NIGHTFORGE_COVERAGE_TEST="\$name"
export LLVM_PROFILE_FILE="$WORK/profiles/\$name-%p.profraw"
export PATH="$WORK/bin:\$PATH"
if bash "\$1/run.sh" > "$OUT/logs/\$name.log" 2>&1; then
  echo "✓ \$name"
else
  echo "✗ \$name (build/coverage/logs/\$name.log)"
  touch "$WORK/failed"
fi
EOF
chmod +x "$WORK/run-one.sh"

echo "▸ Running ${#TESTS[@]} test series with coverage …"
printf '%s\n' "${TESTS[@]}" | xargs -P "$JOBS" -n 1 "$WORK/run-one.sh"

shopt -s nullglob
profiles=("$WORK"/profiles/*.profraw)
objects=("$WORK"/objects/*)
if [ ${#profiles[@]} -eq 0 ] || [ ${#objects[@]} -eq 0 ]; then
  echo "✗ No coverage data (did any Swift test build?)" >&2
  exit 1
fi
xcrun llvm-profdata merge -sparse "${profiles[@]}" -o "$WORK/merged.profdata"

# llvm-cov takes the first binary plainly and every further one after -object.
args=("${objects[0]}")
for object in "${objects[@]:1}"; do args+=(-object "$object"); done
SOURCES=$(ls "$ROOT"/Sources/Nightforge/*.swift)
# shellcheck disable=SC2086
xcrun llvm-cov report -instr-profile "$WORK/merged.profdata" "${args[@]}" $SOURCES \
  | sed "s|$ROOT/||" > "$OUT/report.txt"
if [ "$HTML" = 1 ]; then
  # shellcheck disable=SC2086
  xcrun llvm-cov show -format=html -show-line-counts-or-regions -output-dir "$OUT/html" \
    -instr-profile "$WORK/merged.profdata" "${args[@]}" $SOURCES
  echo "▸ build/coverage/html/index.html"
fi
if [ "$FILES" = 1 ]; then
  mkdir -p "$OUT/files"
  for source in $SOURCES; do
    # shellcheck disable=SC2086
    xcrun llvm-cov show -show-line-counts-or-regions -instr-profile "$WORK/merged.profdata" "${args[@]}" "$source" \
      > "$OUT/files/$(basename "$source").txt"
  done
  echo "▸ build/coverage/files/"
fi

cat "$OUT/report.txt"
echo "▸ build/coverage/report.txt"
if [ -e "$WORK/failed" ]; then
  echo "✗ Some tests failed; their files count as far as they got." >&2
  exit 1
fi
