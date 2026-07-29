#!/usr/bin/env bash
# Build a Debian source package from the Flutter Linux bundle and upload it
# to ppa:dhivalabs/retrobeat.
#
# Usage: bash tool/build_and_upload_ppa.sh [--no-rebuild]
#   --no-rebuild  Skip 'flutter build linux' and reuse the existing bundle.
#
# Prerequisites:
#   - debuild, dput installed
#   - GPG key 3D8D857AAF4D50E6 registered with Launchpad
#   - ~/.dput.cf configured (see below)

set -euo pipefail
cd "$(dirname "$0")/.."

REBUILD=1
for arg in "$@"; do [[ "$arg" == "--no-rebuild" ]] && REBUILD=0; done

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //;s/+.*//')
GPG_KEY=3D8D857AAF4D50E6
PPA=dhiva-apps   # dput stanza in ~/.dput.cf → ppa:dhiva-labs/apps

echo "==> RetroBeat $VERSION — PPA build"

if [[ $REBUILD -eq 1 ]]; then
  echo "==> Building Linux release bundle..."
  CC=/snap/flutter/current/usr/bin/clang \
  CXX=/snap/flutter/current/usr/bin/clang++ \
  flutter build linux --release
fi

BUNDLE=build/linux/x64/release/bundle
[[ -d "$BUNDLE" ]] || { echo "ERROR: $BUNDLE not found. Run without --no-rebuild."; exit 1; }

WORKDIR=$(mktemp -d)
PKGDIR="$WORKDIR/retrobeat_${VERSION}"
echo "==> Staging in $PKGDIR"
mkdir -p "$PKGDIR"

# Bundle and icon
cp -rp "$BUNDLE" "$PKGDIR/bundle"
cp assets/icon/icon.png "$PKGDIR/icon.png"

# Debian packaging
cp -r packaging/debian "$PKGDIR/debian"
chmod +x "$PKGDIR/debian/rules"

# Build the signed source package
(cd "$PKGDIR" && debuild -S -sa -k"$GPG_KEY")

CHANGES="$WORKDIR/retrobeat_${VERSION}_source.changes"
echo "==> Uploading to $PPA"
dput "$PPA" "$CHANGES"

echo "==> Done. Monitor build at: https://launchpad.net/~dhiva-labs/+archive/ubuntu/apps/+packages"
