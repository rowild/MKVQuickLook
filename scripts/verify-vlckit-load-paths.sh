#!/bin/zsh

# Checks a built MKVQuickLook.app: VLCKit exists once (in Contents/Frameworks), and
# every VLCKit reference of the app and of the Quick Look extension resolves to it.
# A wrong layout crashes the extension at launch ("Library not loaded"), so the
# install and release scripts run this before they ship a bundle.
# Usage: scripts/verify-vlckit-load-paths.sh path/to/MKVQuickLook.app

set -euo pipefail

APP="${1:?Usage: $0 path/to/MKVQuickLook.app}"
failures=0

copies="$(cd "$APP" && find . -type d -name VLCKit.framework | sed 's|^\./||' | sort)"
if [[ "$copies" != "Contents/Frameworks/VLCKit.framework" ]]; then
  echo "error: expected VLCKit only in Contents/Frameworks, found: ${copies//$'\n'/, }" >&2
  failures=$((failures + 1))
fi

for macos_dir in "$APP/Contents/MacOS" "$APP/Contents/PlugIns/MKVQuickLookPreviewExtension.appex/Contents/MacOS"; do
  found_reference=0
  for binary in "$macos_dir"/*(N.); do
    [[ "$(basename "$binary")" == __* ]] && continue
    for reference in $(otool -L "$binary" | awk '/VLCKit\.framework/ {print $1}' | sort -u); do
      found_reference=1
      target="${reference/@loader_path/$macos_dir}"
      target="${target/@executable_path/$macos_dir}"
      if [[ ! -f "$target" ]]; then
        echo "error: $(basename "$binary") cannot load $reference (no file at $target)" >&2
        failures=$((failures + 1))
      fi
    done
  done
  if (( found_reference == 0 )); then
    echo "error: no binary in $macos_dir references VLCKit" >&2
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  exit 1
fi
echo "VLCKit layout OK: one copy, all references resolve"
