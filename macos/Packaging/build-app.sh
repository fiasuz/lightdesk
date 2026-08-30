#!/bin/bash
# Hand-assembles LiteDesk.app since this is a plain SPM package, not an Xcode
# project (swift package generate-xcodeproj is deprecated/removed in current
# toolchains). Produces macos/build/LiteDesk.app and macos/dist/LiteDesk-<version>-mac.zip.
set -euo pipefail

VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"

BUILD_DIR="$MACOS_DIR/build"
DIST_DIR="$MACOS_DIR/dist"
APP_DIR="$BUILD_DIR/LiteDesk.app"

echo "==> swift build -c release"
(cd "$MACOS_DIR" && swift build -c release)

BINARY_PATH="$MACOS_DIR/.build/release/LiteDesk"
if [ ! -f "$BINARY_PATH" ]; then
    echo "error: release binary not found at $BINARY_PATH" >&2
    exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/LiteDesk"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> ad-hoc signing"
codesign --sign - --force --deep "$APP_DIR"

echo "==> verifying signature"
codesign --verify --verbose "$APP_DIR"

echo "==> zipping to dist/"
mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/LiteDesk-${VERSION}-mac.zip"
rm -f "$ZIP_PATH"
(cd "$BUILD_DIR" && zip -qr "$ZIP_PATH" "LiteDesk.app")

echo "==> done: $APP_DIR"
echo "==> done: $ZIP_PATH"
