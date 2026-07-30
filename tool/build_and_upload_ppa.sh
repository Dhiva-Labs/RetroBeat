#!/usr/bin/env bash
# Build a Debian source package from the Flutter Linux bundle and upload it
# to ppa:dhiva-labs/apps.
#
# Usage: bash tool/build_and_upload_ppa.sh [--no-rebuild] [--build-only]
#   --no-rebuild   Skip 'flutter build linux' and reuse the existing bundle.
#   --build-only   Stage and pack the source package (unsigned) then print
#                  the debsign + dput commands to run manually in a terminal
#                  (needed when GPG pinentry requires an interactive session).
#
# Prerequisites:
#   - debuild, dput installed
#   - GPG key 3D8D857AAF4D50E6 registered with Launchpad
#   - ~/.dput.cf configured with [dhiva-apps] stanza

set -euo pipefail
cd "$(dirname "$0")/.."

REBUILD=1
BUILD_ONLY=0
for arg in "$@"; do
  [[ "$arg" == "--no-rebuild" ]] && REBUILD=0
  [[ "$arg" == "--build-only" ]] && BUILD_ONLY=1
done

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //;s/+.*//')
# PPA_SUFFIX lets us re-upload the same upstream version with a fixed package
# (e.g. +ppa1, +ppa2) without changing the Flutter app version.
PPA_SUFFIX=${PPA_SUFFIX:-+ppa1}
PKG_VERSION="${VERSION}${PPA_SUFFIX}"
GPG_KEY=3D8D857AAF4D50E6
PPA=dhiva-apps   # dput stanza in ~/.dput.cf → ppa:dhiva-labs/apps

echo "==> RetroBeat $PKG_VERSION — PPA build"

if [[ $REBUILD -eq 1 ]]; then
  echo "==> Building Linux release bundle..."
  CC=/snap/flutter/current/usr/bin/clang \
  CXX=/snap/flutter/current/usr/bin/clang++ \
  flutter build linux --release
fi

BUNDLE=build/linux/x64/release/bundle
[[ -d "$BUNDLE" ]] || { echo "ERROR: $BUNDLE not found. Run without --no-rebuild."; exit 1; }

WORKDIR=/tmp/retrobeat-ppa
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
PKGDIR="$WORKDIR/retrobeat_${PKG_VERSION}"
echo "==> Staging in $PKGDIR"
mkdir -p "$PKGDIR"

# Bundle and icon
cp -rp "$BUNDLE" "$PKGDIR/bundle"
cp assets/icon/icon.png "$PKGDIR/icon.png"

# Debian packaging
cp -r packaging/debian "$PKGDIR/debian"
chmod +x "$PKGDIR/debian/rules"

if [[ $BUILD_ONLY -eq 1 ]]; then
  # Build unsigned — caller will sign and upload in an interactive terminal
  (cd "$PKGDIR" && debuild -S -sa -us -uc)
  CHANGES="$WORKDIR/retrobeat_${PKG_VERSION}_source.changes"
  echo ""
  echo "==> Source package built (unsigned). Run these two commands in a terminal:"
  echo "    debsign -k $GPG_KEY $CHANGES"
  echo "    dput $PPA $CHANGES"
else
  # Build and sign in one shot (requires interactive GPG pinentry)
  (cd "$PKGDIR" && debuild -S -sa -k"$GPG_KEY")
  CHANGES="$WORKDIR/retrobeat_${PKG_VERSION}_source.changes"
  echo "==> Uploading to $PPA"
  dput "$PPA" "$CHANGES"
  echo "==> Done. Monitor build at: https://launchpad.net/~dhiva-labs/+archive/ubuntu/apps/+packages"
fi
