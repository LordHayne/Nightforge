# Sourced by scripts/run-tests.sh and scripts/coverage.sh, from the root of the repository.
#   compile_app_once <jobs> [flags for every file]
# Compiles the app ahead and puts scripts/testbuild/swiftc first on PATH (see there). NIGHTFORGE_TEST_FULL_BUILDS=1, or anything
# that keeps the app from being compiled ahead short of a real compile error, leaves every series building the old way.
compile_app_once() {
  local jobs="$1" folder rc=0 started=$SECONDS
  shift
  [ -z "${NIGHTFORGE_TEST_FULL_BUILDS:-}" ] || return 0
  # shellcheck source=scripts/sdk-lib.sh
  . scripts/sdk-lib.sh && nightforge_pick_sdk
  NIGHTFORGE_REAL_SWIFTC="$(xcrun -f swiftc)" || return 0
  export NIGHTFORGE_REAL_SWIFTC
  folder="$(scripts/testbuild/swiftc --prepare build/test-objects "$jobs" "$@")" || rc=$?
  case "$rc" in
    0)
      echo "▸ The app is compiled ($((SECONDS - started)) s), each series now builds only its own files"
      ;;
    1)
      echo "✗ The app doesn't compile: every series that needs all of it fails with that" >&2
      ;;
    *)
      echo "▸ The app couldn't be compiled ahead, so each series compiles it itself"
      return 0
      ;;
  esac
  export NIGHTFORGE_TEST_OBJECTS="$folder"
  export PATH="$PWD/scripts/testbuild:$PATH"
}
