#!/bin/bash
# Installs or updates Nightforge from its newest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/LordHayne/Nightforge/main/scripts/install.sh | bash
#
# Downloaded this way the app carries no quarantine flag, so macOS opens it without the
# "can't be verified" detour (Nightforge is free and not registered with Apple).
# For testing: NIGHTFORGE_ZIP (a local zip), NIGHTFORGE_INSTALL_DIR, NIGHTFORGE_APPLICATIONS (in place of
# /Applications; HOME stands in for the home folder), NIGHTFORGE_NO_QUIT (leaves a running Nightforge alone)
# and NIGHTFORGE_NO_OPEN.
set -euo pipefail

REPO="LordHayne/Nightforge"
APP="Nightforge.app"
APPLICATIONS="${NIGHTFORGE_APPLICATIONS:-/Applications}"

fail() { echo "✗ $*" >&2; exit 1; }

# Only a release the maintainer signed is installed (docs/SICHERHEIT-0.3.md › Signierte Releases), so a
# release file added or swapped on GitHub doesn't reach new players. The public keys come from main, like
# this script: whoever can change main can change both. While SigningKeys.swift on main has no keys, only
# 0.3.0 installs. For testing: NIGHTFORGE_RELEASE (in place of GitHub's newest release; file:// works) and
# NIGHTFORGE_SIGNING_KEYS (in place of main's SigningKeys.swift). A NIGHTFORGE_ZIP is taken as it is.
RELEASE="${NIGHTFORGE_RELEASE:-https://api.github.com/repos/$REPO/releases/latest}"
SIGNING_KEYS="${NIGHTFORGE_SIGNING_KEYS:-https://raw.githubusercontent.com/$REPO/main/Sources/Nightforge/SigningKeys.swift}"
# Nightforge 0.3.0 came before the signatures: its zip counts by its SHA-256 (GitHub's, of the immutable release).
UNSIGNED_030="fdab8aec7d2bcb55d2d1adb6053a4ed452b30bdce45f2fa5d18ed812cc46aa4a"

# Whether the zip $1 is Nightforge's: 0.3.0's, or one with a line in $1.sig that holds for one of the keys.
is_nightforge() {
  [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$UNSIGNED_030" ] && return 0
  local keys
  keys="$(curl -fsSL "$SIGNING_KEYS" | sed -n 's|^    static let [a-z]* = "\([A-Za-z0-9+/]\{43\}=\)"$|\1|p' || true)"
  [ -n "$keys" ] && [ -s "$1.sig" ] || return 1
  # shellcheck disable=SC2086
  ed25519_verify "$1" "$1.sig" $keys
}

# Ed25519 (RFC 8032) in the Perl every Mac has: its LibreSSL has none, Python and Swift need the developer
# tools. The app's check (Sources/Nightforge/Signature.swift): one of the first eight lines of the .sig
# that holds with one of the keys is enough. A signature holds when [S]B - [h]A encodes to its R.
ed25519_verify() {
  /usr/bin/perl - "$@" <<'PERL'
use strict;
use warnings;
use Digest::SHA;
use MIME::Base64 qw(decode_base64);
use Math::BigInt;

my ($file, $sigfile, @keys) = @ARGV;
my $p = Math::BigInt->new(2)->bpow(255)->bsub(19);
my $L = Math::BigInt->new(2)->bpow(252)->badd("27742317777372353535851937790883648493");
sub md { my $x = shift; $x->bmod($p); $x }
sub inv { $_[0]->copy->bmodpow($p - 2, $p) }
my $d = md(Math::BigInt->new(-121665) * inv(Math::BigInt->new(121666)));
my $I = Math::BigInt->new(2)->bmodpow(($p - 1) / 4, $p);
# Numbers are 32 bytes, little-endian.
sub num { Math::BigInt->from_hex(unpack("H*", scalar reverse $_[0])) }
sub octets { my $h = substr($_[0]->as_hex, 2); reverse pack("H*", ("0" x (64 - length $h)) . $h) }
sub x_of {
  my ($y, $sign) = @_;
  my $x2 = md(($y * $y - 1) * inv(md($d * $y * $y + 1)));
  return $sign ? undef : Math::BigInt->new(0) if $x2->is_zero;
  my $x = $x2->copy->bmodpow(($p + 3) / 8, $p);
  $x = md($x * $I) unless md($x * $x - $x2)->is_zero;
  return undef unless md($x * $x - $x2)->is_zero;
  $x = $p - $x if $x->is_odd != $sign;
  $x
}
# Points in extended coordinates (X, Y, Z, T).
sub point {
  my $n = num($_[0]);
  my $sign = $n->copy->brsft(255)->is_one ? 1 : 0;
  my $y = $n->band(Math::BigInt->new(2)->bpow(255)->bsub(1));
  return undef if $y >= $p;
  my $x = x_of($y, $sign);
  defined $x ? [$x, $y, Math::BigInt->new(1), md($x * $y)] : undef
}
sub add {
  my ($P, $Q) = @_;
  my $A = md(($P->[1] - $P->[0]) * ($Q->[1] - $Q->[0]));
  my $B = md(($P->[1] + $P->[0]) * ($Q->[1] + $Q->[0]));
  my $C = md($P->[3] * 2 * $d * $Q->[3]);
  my $D = md($P->[2] * 2 * $Q->[2]);
  my ($E, $F, $G, $H) = ($B - $A, $D - $C, $D + $C, $B + $A);
  [md($E * $F), md($G * $H), md($F * $G), md($E * $H)]
}
sub mul {
  my ($s, $P) = @_;
  my $Q = [map { Math::BigInt->new($_) } 0, 1, 1, 0];
  for my $bit (reverse split //, substr($s->as_bin, 2)) {
    $Q = add($Q, $P) if $bit;
    $P = add($P, $P);
  }
  $Q
}
sub encode {
  my $P = shift;
  my $z = inv($P->[2]);
  my ($x, $y) = (md($P->[0] * $z), md($P->[1] * $z));
  octets($y->badd($x->is_odd ? Math::BigInt->new(2)->bpow(255) : 0))
}
my $By = md(Math::BigInt->new(4) * inv(Math::BigInt->new(5)));
my $Bx = x_of($By, 0);
my $base = [$Bx, $By, Math::BigInt->new(1), md($Bx * $By)];

sub holds {
  my ($key, $sig) = @_;
  my $A = point($key) or return 0;
  my ($R, $S) = (substr($sig, 0, 32), num(substr($sig, 32)));
  return 0 if $S >= $L;
  my $h = num(Digest::SHA->new(512)->add($R, $key)->addfile($file, "b")->digest)->bmod($L);
  my $hA = mul($h, $A);
  encode(add(mul($S, $base), [md(-$hA->[0]), $hA->[1], $hA->[2], md(-$hA->[3])])) eq $R
}

open my $in, "<", $sigfile or exit 1;
my @lines = grep { /\S/ } map { s/\s+//gr } <$in>;
$#lines = 7 if $#lines > 7;
for my $sig (map { decode_base64($_) } @lines) {
  next unless length $sig == 64;
  for my $key (map { decode_base64($_) } @keys) {
    exit 0 if length $key == 32 && holds($key, $sig);
  }
}
exit 1;
PERL
}

# Quits an app only when it runs: AppleScript would start one it is told to quit.
quit_running() {
  pgrep -qf "$2.app/Contents/MacOS/$2" || return 0
  osascript -e "tell application id \"$1\" to quit" >/dev/null 2>&1 || true
}

# An update replaces the copy that is there, in its folder: a second one elsewhere would leave the old
# version to whatever Spotlight or the Dock opens. With a copy in both folders the one opened last wins,
# by the date the Finder shows as "Last opened"; with neither date (never opened, Spotlight off) the one in
# /Applications, where a fresh Mac gets it. A copy in a folder this user can't write to can't be replaced.
install_target() {
  local dir name date best="" best_date=""
  for dir in "$APPLICATIONS" "$HOME/Applications"; do
    for name in "$APP" Nachtschicht.app; do
      [ -d "$dir/$name" ] && [ -w "$dir" ] || continue
      date="$(mdls -raw -name kMDItemLastUsedDate "$dir/$name" 2>/dev/null || true)"
      [ "$date" = "(null)" ] && date=""
      # The dates read "2026-11-02 21:15:04 +0000", so a later one sorts after an earlier one.
      if [ -z "$best" ] || [[ "$date" > "$best_date" ]]; then
        best="$dir"
        best_date="$date"
      fi
    done
  done
  if [ -n "$best" ]; then
    echo "$best"
  elif [ -w "$APPLICATIONS" ]; then
    echo "$APPLICATIONS"
  else
    echo "$HOME/Applications"
  fi
}

# Everything runs from here, called on the script's last line: a download cut short by `curl | bash`
# then runs nothing at all instead of half the steps.
main() {
  [ "$(uname -s)" = "Darwin" ] || fail "Nightforge runs on macOS only."
  [ "$(uname -m)" = "arm64" ] || fail "Nightforge needs a Mac with Apple silicon (M1 or newer)."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 26 ] || fail "Nightforge needs macOS 26 Tahoe or newer."

  target="${NIGHTFORGE_INSTALL_DIR:-$(install_target)}"
  mkdir -p "$target"

  work="$(mktemp -d)"
  trap 'rm -rf -- "${work:?}"' EXIT

  if [ -n "${NIGHTFORGE_ZIP:-}" ]; then
    cp "$NIGHTFORGE_ZIP" "$work/Nightforge.zip"
  else
    echo "▸ Looking for the newest version …"
    # `|| true`: with pipefail, no match (offline, rate limit) would end the script without a word.
    url="$(curl -fsSL "$RELEASE" \
      | grep -o '"browser_download_url": *"[^"]*Nightforge-[^"]*\.zip"' | head -1 | cut -d'"' -f4 || true)"
    [ -n "$url" ] || fail "No release found. Check your internet connection and try again."
    echo "▸ Downloading ${url##*/} …"
    curl -fL --progress-bar -o "$work/Nightforge.zip" "$url"
    curl -fsSL -o "$work/Nightforge.zip.sig" "$url.sig" 2>/dev/null || true
    # Nothing of the download is unpacked before it holds.
    is_nightforge "$work/Nightforge.zip" \
      || fail "This Nightforge isn't signed by its maintainer, so it wasn't installed. Please tell us: https://github.com/$REPO/issues"
  fi

  ditto -x -k "$work/Nightforge.zip" "$work/unpacked"
  [ -d "$work/unpacked/$APP" ] || fail "The download is incomplete. Please try again."

  # Quit a running copy so it can be replaced.
  if [ -z "${NIGHTFORGE_NO_QUIT:-}" ]; then
    quit_running io.github.lordhayne.nightforge Nightforge
    # Nightforge's earlier name: replaced by this install (its data moves over on first start).
    quit_running local.thomas.nachtschicht Nachtschicht
    sleep 1
  fi

  rm -rf -- "${target:?}/$APP" "${target:?}/Nachtschicht.app"
  ditto "$work/unpacked/$APP" "$target/$APP"
  xattr -dr com.apple.quarantine "$target/$APP" 2>/dev/null || true

  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
  echo "✓ Nightforge $version installed in $target"
  for other in "$APPLICATIONS" "$HOME/Applications"; do
    if [ "$other" != "$target" ] && [ -d "$other/$APP" ]; then
      echo "  An older copy is still in $other. It stays as it was; you can move it to the Bin."
    fi
  done
  [ -n "${NIGHTFORGE_NO_OPEN:-}" ] || open "$target/$APP"
}

main "$@"
