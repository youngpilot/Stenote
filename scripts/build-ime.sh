#!/usr/bin/env bash
# Build SteneoIM input method extension and install to ~/Library/Input Methods/
# Usage: bash scripts/build-ime.sh [--notarize]
#   --notarize  Sign with Developer ID, submit for notarization, and staple.
#               Required for Gatekeeper to accept the IME on macOS 14+.
#               Without this flag, run: sudo spctl --add ~/Library/Input\ Methods/SteneoIM.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_DIR/SteneoIM"
BUILD_DIR="$PROJECT_DIR/.build-ime"
APP_BUNDLE="$BUILD_DIR/SteneoIM.app"
INSTALL_DIR="$HOME/Library/Input Methods"
INSTALLED_APP="$INSTALL_DIR/SteneoIM.app"

BUNDLE_ID="com.youngpilot.Steneo.InputMethod"
EXECUTABLE="SteneoIM"
TEAM_ID="${STENOTE_TEAM_ID:?Set STENOTE_TEAM_ID env var (your Apple Developer Team ID, e.g. ABCDE12345)}"
SIGNER="Developer ID Application: ${STENOTE_SIGNER_NAME:?Set STENOTE_SIGNER_NAME env var (e.g. 'Your Name')} ($TEAM_ID)"

NOTARIZE=false
for arg in "$@"; do
    [[ "$arg" == "--notarize" ]] && NOTARIZE=true
done

echo "==> Building SteneoIM..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

SOURCES=(
    "$SRC_DIR/main.swift"
    "$SRC_DIR/NotificationBridge.swift"
    "$SRC_DIR/SteneoInputController.swift"
)

swiftc \
    -target arm64-apple-macosx15.2 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework AppKit \
    -framework InputMethodKit \
    -o "$BUILD_DIR/$EXECUTABLE" \
    "${SOURCES[@]}"

echo "==> Assembling app bundle..."

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$SRC_DIR/Info.plist"    "$APP_BUNDLE/Contents/Info.plist"

if $NOTARIZE; then
    echo "==> Signing with Developer ID (hardened runtime)..."
    codesign --force --deep \
        --sign "$SIGNER" \
        --options runtime \
        --entitlements "$SRC_DIR/SteneoIM.entitlements" \
        "$APP_BUNDLE"

    echo "==> Notarizing..."
    ZIP_PATH="$BUILD_DIR/SteneoIM.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile notary --wait
    xcrun stapler staple "$APP_BUNDLE"
    echo "==> Notarization complete."
else
    echo "==> Signing with Developer ID..."
    codesign --force --deep \
        --sign "$SIGNER" \
        --options runtime \
        --entitlements "$SRC_DIR/SteneoIM.entitlements" \
        "$APP_BUNDLE"
fi

echo "==> Installing to ~/Library/Input Methods/..."
if pgrep -f "SteneoIM" &>/dev/null; then
    pkill -f "SteneoIM" || true
    sleep 0.5
fi

rm -rf "$INSTALLED_APP"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

echo "==> Registering input source..."
swift - "$INSTALLED_APP" 2>/dev/null <<'SWIFT' || true
import Carbon
import Foundation
let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path) as CFURL
let result = TISRegisterInputSource(url)
print("TISRegisterInputSource result: \(result)")
SWIFT

if ! $NOTARIZE; then
    echo ""
    echo "NOTE: App is not notarized. To allow TIS to register it, run:"
    echo "  sudo spctl --add \"$INSTALLED_APP\""
    echo "Then re-run: bash scripts/build-ime.sh"
    echo ""
    echo "Or to notarize properly: bash scripts/build-ime.sh --notarize"
fi

echo ""
echo "Done. After Gatekeeper approval:"
echo "  1. System Settings → Keyboard → Input Sources → '+' → add Steneo"
echo "  2. Switch to Steneo input source in any text field"
echo "  3. Test: swift scripts/test-ime.swift"
