#!/usr/bin/env bash
set -euo pipefail

# Build PocketDSH on macOS.
# Usage:
#   scripts/build-app.sh            # macOS app
#   SCHEME=PocketDSH-iOS scripts/build-app.sh
#   DESTINATION='platform=iOS Simulator,name=iPhone 16' scripts/build-app.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/App"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

SCHEME="${SCHEME:-PocketDSH-macOS}"
if [[ -z "${DESTINATION:-}" ]]; then
  if [[ "$SCHEME" == *iOS* ]]; then
    DESTINATION="generic/platform=iOS Simulator"
  else
    DESTINATION="platform=macOS"
  fi
fi

xcodebuild \
  -project PocketDSH.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  build
