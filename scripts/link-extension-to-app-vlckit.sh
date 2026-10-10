#!/bin/zsh

# Xcode build step of the Quick Look extension target (see project.yml).
#
# VLCKit's install name is @loader_path/../Frameworks/VLCKit.framework/..., so every
# binary that links it looks for VLCKit in the Frameworks folder next to itself.
# The app embeds VLCKit once. This step points the extension's reference at the
# app's copy:
#   MKVQuickLook.app/Contents/PlugIns/X.appex/Contents/MacOS/../../../../Frameworks
#   = MKVQuickLook.app/Contents/Frameworks
# Debug builds keep the extension's code in X.debug.dylib, so both files are checked.

set -euo pipefail

OLD_REFERENCE="@loader_path/../Frameworks/VLCKit.framework/Versions/A/VLCKit"
NEW_REFERENCE="@loader_path/../../../../Frameworks/VLCKit.framework/Versions/A/VLCKit"
MACOS_DIR="${1:-$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH}"
EXECUTABLE="${2:-$EXECUTABLE_NAME}"

checked=0
for binary in "$MACOS_DIR/$EXECUTABLE" "$MACOS_DIR/$EXECUTABLE.debug.dylib"; do
  [[ -f "$binary" ]] || continue
  # Universal binaries list each architecture separately; one unique value is expected.
  references="$(otool -L "$binary" | awk '/VLCKit\.framework/ {print $1}' | sort -u)"
  [[ -n "$references" ]] || continue

  if [[ "$references" == "$OLD_REFERENCE" ]]; then
    install_name_tool -change "$OLD_REFERENCE" "$NEW_REFERENCE" "$binary"
    # install_name_tool invalidates the linker's ad hoc signature, and arm64 refuses
    # to run unsigned code. Xcode's signing step (when enabled) signs again later.
    codesign --force --sign - --timestamp=none "$binary"
    echo "note: $(basename "$binary") now loads VLCKit from the app bundle"
  elif [[ "$references" != "$NEW_REFERENCE" ]]; then
    echo "error: unexpected VLCKit reference in $binary: $references" >&2
    exit 1
  fi
  checked=$((checked + 1))
done

if (( checked == 0 )); then
  echo "error: no extension binary in $MACOS_DIR references VLCKit" >&2
  exit 1
fi
