#!/bin/zsh

# Prints the CHANGELOG.md section for one version, without its "## <version>" heading.
# Usage: scripts/changelog-section.sh 0.1.7   (a leading "v", as in a tag, is accepted)
# Exits with an error when the section is missing or empty, so a release cannot be
# published with empty notes.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG_PATH="${CHANGELOG_PATH:-$ROOT_DIR/CHANGELOG.md}"
VERSION="${1:?Usage: $0 <version>}"
VERSION="${VERSION#v}"

SECTION="$(awk -v version="$VERSION" '
  $0 == "## " version || index($0, "## " version " ") == 1 { inSection = 1; next }
  inSection && /^## / { exit }
  inSection && !started && /^[[:space:]]*$/ { next }
  inSection { started = 1; print }
' "$CHANGELOG_PATH")"

if [[ -z "${SECTION//[[:space:]]/}" ]]; then
  echo "No CHANGELOG.md section found for version $VERSION." >&2
  exit 1
fi

print -r -- "$SECTION"
