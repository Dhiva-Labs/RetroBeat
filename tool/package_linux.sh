#!/usr/bin/env bash
# Packs the Linux release bundle (flutter build linux --release) into
# <out-dir>/RetroBeat-<version>-linux-<arch>.tar.gz.
#
# The architecture comes from the machine this runs on (x64 or arm64), because
# Flutter builds for the host. Set ASSET_VERSION (for example a release tag
# such as v1.1.1) to override the version taken from pubspec.yaml.
#
# Usage: tool/package_linux.sh [out-dir]    (default out-dir: dist)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-dist}"

case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "error: unsupported machine '$(uname -m)' (x86_64 or aarch64)" >&2
    exit 1
    ;;
esac

RELEASE_DIR="build/linux/$ARCH/release"
[ -x "$RELEASE_DIR/bundle/retro_beat" ] || {
  echo "error: $RELEASE_DIR/bundle/retro_beat not found; run 'flutter build linux --release' first" >&2
  exit 1
}

VERSION="${ASSET_VERSION:-}"
VERSION="${VERSION#v}"
if [ -z "$VERSION" ]; then
  VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
fi

NAME="RetroBeat-${VERSION}-linux-${ARCH}"
mkdir -p "$OUT_DIR"
tar -czf "$OUT_DIR/$NAME.tar.gz" --owner=0 --group=0 --sort=name \
  --transform "s,^bundle,$NAME," -C "$RELEASE_DIR" bundle
echo "Built: $OUT_DIR/$NAME.tar.gz"
