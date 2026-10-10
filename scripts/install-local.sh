#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MKVQuickLook.xcodeproj"
SCHEME="MKVQuickLook"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
APP_NAME="MKVQuickLook.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_PATH="$INSTALL_DIR/$APP_NAME"
EXTENSION_PATH="$INSTALLED_APP_PATH/Contents/PlugIns/MKVQuickLookPreviewExtension.appex"
# VLCKit is embedded once, in the app; the extension loads that copy.
FRAMEWORK_PATH="$INSTALLED_APP_PATH/Contents/Frameworks/VLCKit.framework"
# A fixed build folder: searching Xcode's shared DerivedData could pick up a stale
# build from another copy of this project.
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/install-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
BUILD_LOG="/tmp/mkvquicklook-install-build.log"

"$ROOT_DIR/scripts/bootstrap-vlckit.sh"

echo "==> Building $APP_NAME"
if ! xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build >"$BUILD_LOG" 2>&1; then
  echo "Build failed. Full log: $BUILD_LOG"
  grep -E "error:" "$BUILD_LOG" | head -n 20 || tail -n 30 "$BUILD_LOG"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but the app bundle was not found at:"
  echo "  $APP_PATH"
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP_PATH"
cp -R "$APP_PATH" "$INSTALLED_APP_PATH"

echo "==> Applying ad hoc bundle signatures"
codesign --force --sign - --timestamp=none "$FRAMEWORK_PATH"
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT_DIR/MKVQuickLookPreviewExtension/MKVQuickLookPreviewExtension.entitlements" \
  "$EXTENSION_PATH"
codesign --force --sign - --timestamp=none "$INSTALLED_APP_PATH"

"$ROOT_DIR/scripts/verify-vlckit-load-paths.sh" "$INSTALLED_APP_PATH"

echo "==> Installed to $INSTALLED_APP_PATH"
echo "==> Refreshing Quick Look registration"
"$ROOT_DIR/scripts/reset-quicklook.sh"

echo "==> Forcing Launch Services to register the app bundle"
'/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister' -f "$INSTALLED_APP_PATH" >/dev/null 2>&1 || true

echo "==> Registering extension with pluginkit"
pluginkit -a "$EXTENSION_PATH" >/dev/null 2>&1 || true

echo "==> Opening app once to help extension discovery"
open "$INSTALLED_APP_PATH"

APP_VERSION="$(defaults read "$INSTALLED_APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
APP_BUILD="$(defaults read "$INSTALLED_APP_PATH/Contents/Info" CFBundleVersion 2>/dev/null || echo "unknown")"
PLUGIN_VERSION="$(pluginkit -m -A -D -i com.robertwildling.MKVQuickLook.PreviewExtension 2>/dev/null | sed -E -n 's/.*\(([^)]*)\).*/\1/p' | head -n 1)"

echo
echo "Installed app:"
echo "  $INSTALLED_APP_PATH"
echo "Installed version:"
echo "  $APP_VERSION (build $APP_BUILD)"
echo "Registered extension version:"
echo "  ${PLUGIN_VERSION:-unknown}"
echo
echo "Next step:"
echo "  In Finder, select a supported sample file and press Space."
