#!/bin/bash
# Usage: ./scripts/release.sh 1.0   -- builds the disk image and publishes it as a GitHub Release (requires `gh auth login`).
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -eq 1 ] || { echo "usage: $0 <version, e.g. 1.0>"; exit 1; }
./scripts/make-dmg.sh
gh release create "v$1" dist/QuizBowlStatkeeper.dmg --title "Quiz Bowl Statkeeper for Mac $1" \
  --notes "Download QuizBowlStatkeeper.dmg, open it, and drag the app to Applications. The app is not notarized: if macOS blocks it, open System Settings > Privacy & Security and click \"Open Anyway\"."
