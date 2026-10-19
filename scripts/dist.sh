#!/bin/bash
# Every installer bumps the patch version, builds, packs a .dmg and installs it in /Applications.
#   scripts/dist.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IFS=. read -r MAJOR MINOR PATCH < "$ROOT/VERSION"
VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
echo "$VERSION" > "$ROOT/VERSION"

"$ROOT/scripts/build.sh"

STAGE="$(mktemp -d)"
cp -R "$ROOT/dist/Windows.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$ROOT/dist/Windows-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Windows by Ciro Cesar Maciel $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# Install from the packed image, the same bytes a tester gets.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -mountpoint "$MOUNT" >/dev/null
WAS_RUNNING="$(osascript -e 'application id "click.ciromaciel.windows" is running' 2>/dev/null || echo false)"
osascript -e 'tell application id "click.ciromaciel.windows" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/Windows.app
cp -R "$MOUNT/Windows.app" /Applications/
hdiutil detach "$MOUNT" >/dev/null
echo "Installed /Applications/Windows.app ($VERSION) from $DMG"
# The person was using it: open the new version in its place.
if [ "$WAS_RUNNING" = "true" ]; then open -b click.ciromaciel.windows; echo "Reopened Windows $VERSION"; fi
