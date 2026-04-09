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
FRAMEWORK_PATH="$EXTENSION_PATH/Contents/Frameworks/VLCKit.framework"

echo "==> Building $APP_NAME"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/mkvquicklook-install-build.log 2>&1

APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*MKVQuickLook*/Build/Products/$CONFIGURATION/$APP_NAME" | tail -n 1)"

if [[ -z "$APP_PATH" ]]; then
  echo "Build succeeded but the app bundle could not be located."
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

echo "==> Installed to $INSTALLED_APP_PATH"
echo "==> Refreshing Quick Look registration"
"$ROOT_DIR/scripts/reset-quicklook.sh"

echo "==> Forcing Launch Services to register the app bundle"
'/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister' -f "$INSTALLED_APP_PATH" >/dev/null 2>&1 || true

echo "==> Registering extension with pluginkit"
pluginkit -a "$EXTENSION_PATH" >/dev/null 2>&1 || true

echo "==> Opening app once to help extension discovery"
open "$INSTALLED_APP_PATH"

echo
echo "Installed app:"
echo "  $INSTALLED_APP_PATH"
echo
echo "Next step:"
echo "  In Finder, select a supported sample file and press Space."
