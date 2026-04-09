#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
TARGET_XCFRAMEWORK="$VENDOR_DIR/VLCKit.xcframework"
TARGET_COPYING="$VENDOR_DIR/VLCKit-COPYING.txt"
TARGET_NEWS="$VENDOR_DIR/VLCKit-NEWS.txt"
VERSION="${VLCKIT_VERSION:-3.7.2}"
PACKAGE_URL="${VLCKIT_PACKAGE_URL:-https://download.videolan.org/cocoapods/prod/VLCKit-3.7.2-3e42ae47-79128878.tar.xz}"
PACKAGE_SHA256="${VLCKIT_PACKAGE_SHA256:-45fc6398c80d1f8dc0e384a9c80704848e9e82a3a382611bf531fa83c198c276}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD_VLCKIT:-0}"

if [[ "$FORCE_DOWNLOAD" != "1" ]] && [[ -d "$TARGET_XCFRAMEWORK" ]] && [[ -f "$TARGET_COPYING" ]] && [[ -f "$TARGET_NEWS" ]]; then
  echo "==> VLCKit $VERSION already present in Vendor/"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
ARCHIVE_PATH="$TMP_DIR/vlckit.tar.xz"
EXTRACT_DIR="$TMP_DIR/extract"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Downloading VLCKit $VERSION"
curl -L "$PACKAGE_URL" -o "$ARCHIVE_PATH"

echo "==> Verifying download"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$PACKAGE_SHA256" ]]; then
  echo "Checksum mismatch for VLCKit package."
  echo "Expected: $PACKAGE_SHA256"
  echo "Actual:   $ACTUAL_SHA256"
  exit 1
fi

echo "==> Extracting package"
mkdir -p "$EXTRACT_DIR"
tar -xJf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"

PACKAGE_ROOT="$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name 'VLCKit - binary package' | head -n 1)"
if [[ -z "$PACKAGE_ROOT" ]]; then
  echo "Could not find extracted VLCKit package root."
  exit 1
fi

mkdir -p "$VENDOR_DIR"
rm -rf "$TARGET_XCFRAMEWORK"
cp -R "$PACKAGE_ROOT/VLCKit.xcframework" "$TARGET_XCFRAMEWORK"
cp "$PACKAGE_ROOT/COPYING.txt" "$TARGET_COPYING"
cp "$PACKAGE_ROOT/NEWS.txt" "$TARGET_NEWS"

echo "==> Installed VLCKit into Vendor/"
