# Which macOS SDK Swift builds against; sourced by build.sh, the signing scripts and the tests, not run.
#   . scripts/sdk-lib.sh && nightforge_pick_sdk
#
# The Command Line Tools ship without SwiftUI's macro plugin, and since the macOS 27 SDK @State is
# such a macro: against it the app fails ("cannot find '$barShown' in scope"). The tools still
# include the 26.5 SDK, which doesn't need the plugin, so builds fall back to it. That happens when
# SDKROOT is empty and also when it names one of the tools' own SDKs that needs the missing plugin
# (MacOSX.sdk, MacOSX27.sdk, …: a shell or an agent that exported `xcrun --show-sdk-path`).
# An SDK chosen elsewhere stays as it is: Xcode's (by xcode-select or DEVELOPER_DIR), one outside
# the tools' SDKs folder, or any once the tools bring the plugin.
#
# NIGHTFORGE_CLT_ROOT names another Command Line Tools folder (tests/test_sdk_choice.py).

# A folder's path with its symbolic links resolved, or nothing when it doesn't exist.
_nightforge_real_dir() {
  [ -n "$1" ] && (cd "$1" 2>/dev/null && pwd -P)
}

# Whether the SDK in $1 declares SwiftUI macros: 0 yes, 1 no, 2 it can't be told (no SwiftUI interface).
_nightforge_sdk_needs_swiftui_macros() {
  local interface found=1
  for interface in "$1"/System/Library/Frameworks/SwiftUI*.framework/Versions/A/Modules/SwiftUI*.swiftmodule/*-apple-macos.swiftinterface \
                   "$1"/System/Library/Frameworks/SwiftUI*.framework/Modules/SwiftUI*.swiftmodule/*-apple-macos.swiftinterface; do
    [ -f "$interface" ] || continue
    found=0
    grep -qF 'module: "SwiftUIMacros"' "$interface" && return 0
  done
  [ "$found" = 0 ] && return 1
  return 2
}

# Prints the SDK to build against instead of SDKROOT's, or nothing when SDKROOT stays as it is.
nightforge_sdk_choice() {
  local clt developer fallback sdk real needs=0
  clt="$(_nightforge_real_dir "${NIGHTFORGE_CLT_ROOT:-/Library/Developer/CommandLineTools}")" || return 0
  fallback="$clt/SDKs/MacOSX26.5.sdk"
  [ -d "$fallback" ] || return 0
  # Only the Command Line Tools lack the plugin; Xcode (xcode-select or DEVELOPER_DIR) has it.
  developer="$(_nightforge_real_dir "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)}")" || return 0
  [ "$developer" = "$clt" ] || return 0
  # The plugin itself, should a later version of the tools bring it.
  if compgen -G "$clt/usr/lib/swift/host/plugins/*SwiftUIMacros*" > /dev/null; then return 0; fi
  if [ -z "${SDKROOT:-}" ]; then
    # Swift's own choice, the tools' MacOSX.sdk; when it can't be told, the fallback as always.
    real="$(_nightforge_real_dir "$clt/SDKs/MacOSX.sdk")" || { echo "$fallback"; return 0; }
    [ "$real" = "$fallback" ] && return 0
    _nightforge_sdk_needs_swiftui_macros "$real" || needs=$?
    [ "$needs" = 1 ] || echo "$fallback"
    return 0
  fi
  real="$(_nightforge_real_dir "$SDKROOT")" || return 0
  case "$real" in
    "$clt"/SDKs/*) ;;
    *) return 0 ;;
  esac
  [ "$real" = "$fallback" ] && return 0
  _nightforge_sdk_needs_swiftui_macros "$real" || needs=$?
  [ "$needs" = 0 ] && echo "$fallback"
  return 0
}

# Exports SDKROOT as nightforge_sdk_choice says, with a line when it replaces one that was set.
nightforge_pick_sdk() {
  local choice
  choice="$(nightforge_sdk_choice)"
  [ -n "$choice" ] || return 0
  if [ -n "${SDKROOT:-}" ]; then
    echo "▸ SDKROOT names ${SDKROOT##*/}, which needs SwiftUI macros the Command Line Tools don't have: building against ${choice##*/}" >&2
  fi
  export SDKROOT="$choice"
}
