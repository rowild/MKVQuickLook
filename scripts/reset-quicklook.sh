#!/bin/zsh

set -euo pipefail

echo "==> Resetting Quick Look generators and cache"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "==> Restarting Quick Look UI services"
killall QuickLookUIService >/dev/null 2>&1 || true
killall quicklookd >/dev/null 2>&1 || true

echo "==> Restarting Finder"
osascript -e 'tell application "Finder" to quit' >/dev/null 2>&1 || true
sleep 1
open -a Finder

echo "==> Done"
