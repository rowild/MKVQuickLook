#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MKVQuickLook.xcodeproj"
SCHEME="${SCHEME:-MKVQuickLook}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
APP_NAME="MKVQuickLook.app"
PRODUCT_NAME="MKVQuickLook"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/release-derived-data}"
BUILD_PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_PATH="$BUILD_PRODUCTS_DIR/$APP_NAME"
EXTENSION_PATH="$APP_PATH/Contents/PlugIns/MKVQuickLookPreviewExtension.appex"
FRAMEWORK_PATH="$EXTENSION_PATH/Contents/Frameworks/VLCKit.framework"
ENTITLEMENTS_PATH="$ROOT_DIR/MKVQuickLookPreviewExtension/MKVQuickLookPreviewExtension.entitlements"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
STAGE_DIR="$ROOT_DIR/.build/dmg-stage"
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1 | tr -d '[:space:]')}"
DMG_NAME="${DMG_NAME:-${PRODUCT_NAME}-v${VERSION}.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ -z "$VERSION" ]]; then
  echo "Could not determine MARKETING_VERSION from project.yml."
  exit 1
fi

"$ROOT_DIR/scripts/bootstrap-vlckit.sh"

echo "==> Building $APP_NAME ($CONFIGURATION)"
rm -rf "$DERIVED_DATA_PATH"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but the app bundle was not found at:"
  echo "  $APP_PATH"
  exit 1
fi

echo "==> Applying ad hoc bundle signatures for distributable packaging"
codesign --force --sign - --timestamp=none "$FRAMEWORK_PATH"
codesign --force --sign - --timestamp=none \
  --entitlements "$ENTITLEMENTS_PATH" \
  "$EXTENSION_PATH"
codesign --force --sign - --timestamp=none "$APP_PATH"

echo "==> Preparing DMG staging folder"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating DMG"
hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Created DMG:"
echo "  $DMG_PATH"
echo
echo "Next step:"
echo "  Upload this DMG to a GitHub Release."
