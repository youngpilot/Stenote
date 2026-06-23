#!/bin/bash
set -euo pipefail

VERSION="0.7.0"
APP_NAME="Talkman"
TEAM_ID="${TALKMAN_TEAM_ID:?Set TALKMAN_TEAM_ID env var (Apple Developer Team ID)}"
BUNDLE_ID="com.youngpilot.Talkman"
IDENTITY="Developer ID Application: ${TALKMAN_SIGNER_NAME:?Set TALKMAN_SIGNER_NAME env var (e.g. 'Your Name')} ($TEAM_ID)"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"

echo "=== Building $APP_NAME v$VERSION ==="

# Clean and build Release
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "$PROJECT_DIR/Talkman.xcodeproj" \
    -scheme Talkman \
    -configuration Release \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    SYMROOT="$BUILD_DIR" \
    build

# The actual app is in Release/ subdirectory
APP_PATH="$BUILD_DIR/Release/$APP_NAME.app"

echo ""
echo "=== Verifying signature ==="
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|Identifier|Runtime"

echo ""
echo "=== Creating ZIP for notarization ==="
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "=== Submitting for notarization ==="
echo "Run this command with your App Store Connect credentials:"
echo ""
echo "  xcrun notarytool submit '$ZIP_PATH' --keychain-profile notary --wait"
echo ""
echo "After notarization succeeds, staple the ticket:"
echo ""
echo "  xcrun stapler staple '$APP_PATH'"
echo ""
echo "Then create the DMG:"
echo ""
echo "  hdiutil create -volname '$APP_NAME' -srcfolder '$APP_PATH' -ov -format UDZO '$DMG_PATH'"
echo ""
echo "Build complete: $APP_PATH"
