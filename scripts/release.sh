#!/bin/bash
set -euo pipefail

VERSION="1.0.0"
APP_NAME="Stenote"
TEAM_ID="${STENOTE_TEAM_ID:?Set STENOTE_TEAM_ID env var (Apple Developer Team ID)}"
BUNDLE_ID="com.youngpilot.Stenote"
IDENTITY="Developer ID Application: ${STENOTE_SIGNER_NAME:?Set STENOTE_SIGNER_NAME env var (e.g. 'Your Name')} ($TEAM_ID)"
NOTARY_PROFILE="${STENOTE_NOTARY_PROFILE:-notary}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DD="$BUILD_DIR/dd"
APP_PATH="$DD/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"

echo "=== Building $APP_NAME v$VERSION ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build into a dedicated derivedDataPath (NOT SYMROOT — SYMROOT splits the SPM
# product dir and breaks resolution of swift-nio's transitive deps).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "$PROJECT_DIR/Stenote.xcodeproj" \
    -scheme Stenote \
    -configuration Release \
    -derivedDataPath "$DD" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build

echo ""
echo "=== Verifying app signature ==="
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|Identifier|Runtime"

echo ""
echo "=== Notarizing app ==="
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"

echo ""
echo "=== Building + notarizing DMG ==="
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo ""
echo "=== Gatekeeper assessment ==="
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" || true
spctl -a -t exec -vv "$APP_PATH" || true

echo ""
echo "Done: $DMG_PATH"
