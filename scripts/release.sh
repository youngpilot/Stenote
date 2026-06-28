#!/bin/bash
set -euo pipefail

VERSION="1.1.0"
DIST_NAME="Steneo"     # user-facing app + DMG name
BUILD_NAME="Stenote"   # internal Xcode product/scheme name (unchanged on purpose)
TEAM_ID="${STENOTE_TEAM_ID:?Set STENOTE_TEAM_ID env var (Apple Developer Team ID)}"
BUNDLE_ID="com.youngpilot.Stenote"   # unchanged: keeps TCC perms + Keychain history key
IDENTITY="Developer ID Application: ${STENOTE_SIGNER_NAME:?Set STENOTE_SIGNER_NAME env var (e.g. 'Your Name')} ($TEAM_ID)"
NOTARY_PROFILE="${STENOTE_NOTARY_PROFILE:-notary}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DD="$BUILD_DIR/dd"
BUILT_APP="$DD/Build/Products/Release/$BUILD_NAME.app"   # what xcodebuild produces (Stenote.app)
APP_PATH="$BUILD_DIR/$DIST_NAME.app"                     # renamed distributable (Steneo.app)
DMG_PATH="$BUILD_DIR/$DIST_NAME-$VERSION.dmg"
ZIP_PATH="$BUILD_DIR/$DIST_NAME-$VERSION.zip"

echo "=== Building $DIST_NAME v$VERSION (internal product: $BUILD_NAME) ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build into a dedicated derivedDataPath (NOT SYMROOT — SYMROOT splits the SPM
# product dir and breaks resolution of swift-nio's transitive deps).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "$PROJECT_DIR/Stenote.xcodeproj" \
    -scheme "$BUILD_NAME" \
    -configuration Release \
    -derivedDataPath "$DD" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build

# Rename the built bundle to the user-facing name. The code signature seals the
# bundle *contents*, not its directory name, so this stays valid (the display
# name comes from CFBundleDisplayName=Steneo; the executable stays Stenote).
echo ""
echo "=== Packaging as $DIST_NAME.app ==="
rm -rf "$APP_PATH"
cp -R "$BUILT_APP" "$APP_PATH"

echo ""
echo "=== Verifying app signature ==="
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|Identifier|Runtime"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo ""
echo "=== Notarizing app ==="
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"

echo ""
echo "=== Building + notarizing DMG ==="
hdiutil create -volname "$DIST_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo ""
echo "=== Gatekeeper assessment ==="
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" || true
spctl -a -t exec -vv "$APP_PATH" || true

echo ""
echo "Done: $DMG_PATH"
