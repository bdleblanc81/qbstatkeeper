#!/bin/bash
# Builds the app and packages it as dist/QuizBowlStatkeeper.dmg (drag-to-Applications disk image).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
APP="Quiz Bowl Statkeeper for Mac.app"
DMG="dist/QuizBowlStatkeeper.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "dist/$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/If macOS blocks the app.txt" <<'TXT'
This app is not notarized by Apple, so macOS blocks it the first time.
1. Drag the app to Applications and try to open it once.
2. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway" next to the app's name.
3. Confirm with your password. After that it opens normally.
TXT
rm -f "$DMG"
hdiutil create -quiet -volname "Quiz Bowl Statkeeper" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
