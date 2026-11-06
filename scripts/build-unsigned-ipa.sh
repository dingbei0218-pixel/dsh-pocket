#!/usr/bin/env bash
# 构建未签名 ipa，交给用户用自己的 Apple ID 签名（AltStore / Sideloadly）。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found: install Xcode first" >&2
  exit 1
fi

DERIVED="build/DerivedData"
rm -rf build/Payload build/PocketDSH-unsigned.ipa
mkdir -p build

xcodebuild \
  -project App/PocketDSH.xcodeproj \
  -scheme PocketDSH \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/DSH Pocket.app"
if [ ! -d "$APP" ]; then
  APP="$DERIVED/Build/Products/Release-iphoneos/PocketDSH.app"
fi
if [ ! -d "$APP" ]; then
  echo "build product not found: $APP" >&2
  exit 1
fi

mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry PocketDSH-unsigned.ipa Payload)
echo "built: build/PocketDSH-unsigned.ipa (unsigned; sign it with your own Apple ID)"
