#!/bin/bash
# Hand-assembles LiteDesk.app since this is a plain SPM package, not an Xcode
# project (swift package generate-xcodeproj is deprecated/removed in current
# toolchains). Produces macos/build/LiteDesk.app and macos/dist/LiteDesk-<version>-mac.zip.
set -euo pipefail

VERSION="${1:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"

BUILD_DIR="$MACOS_DIR/build"
DIST_DIR="$MACOS_DIR/dist"
APP_DIR="$BUILD_DIR/LiteDesk.app"

echo "==> swift build -c release (universal: arm64 + x86_64)"
(cd "$MACOS_DIR" && swift build -c release --arch arm64 --arch x86_64)

BINARY_PATH="$MACOS_DIR/.build/apple/Products/Release/LiteDesk"
if [ ! -f "$BINARY_PATH" ]; then
    echo "error: release binary not found at $BINARY_PATH" >&2
    exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/LiteDesk"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP_DIR/Contents/Info.plist"

echo "==> bundling cloudflared (Internet orqali ulash uchun)"
CACHE_DIR="$SCRIPT_DIR/.cache"
CLOUDFLARED_BASE_URL="https://github.com/cloudflare/cloudflared/releases/latest/download"
mkdir -p "$CACHE_DIR"

fetch_cloudflared_slice() {
    local arch="$1" # arm64 | amd64
    local tgz="$CACHE_DIR/cloudflared-darwin-${arch}.tgz"
    local bin="$CACHE_DIR/cloudflared-darwin-${arch}"
    if [ ! -f "$bin" ]; then
        # stderr, not stdout — this function's stdout is captured via $(...)
        # below and must contain only the final binary path.
        echo "    downloading cloudflared-darwin-${arch}.tgz" >&2
        curl -fL --retry 3 -o "$tgz" "$CLOUDFLARED_BASE_URL/cloudflared-darwin-${arch}.tgz"
        tar -xzf "$tgz" -C "$CACHE_DIR" cloudflared
        mv "$CACHE_DIR/cloudflared" "$bin"
    fi
    echo "$bin"
}

CF_ARM64_BIN="$(fetch_cloudflared_slice arm64)"
CF_AMD64_BIN="$(fetch_cloudflared_slice amd64)"
lipo -create -output "$APP_DIR/Contents/Resources/cloudflared" "$CF_ARM64_BIN" "$CF_AMD64_BIN"
chmod +x "$APP_DIR/Contents/Resources/cloudflared"

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
