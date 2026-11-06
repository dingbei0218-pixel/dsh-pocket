#!/usr/bin/env bash
set -euo pipefail

# Build PocketDSH (iOS) on macOS.
# Usage:
#   scripts/build-app.sh
#   DESTINATION='platform=iOS Simulator,name=iPhone 16' scripts/build-app.sh
#   DESTINATION='generic/platform=iOS' scripts/build-app.sh   # needs signing for device

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/App"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

SCHEME="${SCHEME:-PocketDSH}"
DESTINATION="${DESTINATION:-generic/platform=iOS Simulator}"

xcodebuild \
  -project PocketDSH.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  build
