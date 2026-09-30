#!/bin/bash

# Builds, signs, notarizes and packages the Setapp edition of TransLite as
# the zip that developer.setapp.com expects: the .app plus a 1024x1024
# AppIcon.png at the archive root, packed without Finder metadata.
#
# Unlike publish-release.sh this does NOT bump versions, tag, or touch
# GitHub/Sparkle — Setapp builds ship the version currently in project.yml
# and are uploaded manually (or via the Setapp upload API) for review.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/TransLite"
PROJECT_FILE="$PROJECT_DIR/TransLite.xcodeproj"
PROJECT_YML="$PROJECT_DIR/project.yml"
XCCONFIG="$PROJECT_DIR/Setapp.xcconfig"
PUBLIC_KEY="$PROJECT_DIR/TransLite/setappPublicKey.pem"
ICON_SOURCE="$PROJECT_DIR/TransLite/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
RELEASE_DIR="$ROOT_DIR/releases"
DEVELOPER_ID="${TRANSLITE_DEVELOPER_ID:-Developer ID Application}"
NOTARY_PROFILE="${TRANSLITE_NOTARY_PROFILE:-TransLite}"
TEAM_ID="${TRANSLITE_TEAM_ID:-2DBHSD6G6F}"
EXPECTED_BUNDLE_ID="com.translite.app-setapp"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/release-setapp.sh

Builds the TransLiteSetapp target (Release, universal), signs it with the
Developer ID certificate, notarizes it and produces the submission archive:

  releases/TransLite-Setapp-<version>.zip

Prerequisites:
  - TransLite/Setapp.xcconfig with the Setapp AI OAuth credentials filled in
  - TransLite/TransLite/setappPublicKey.pem downloaded from the Setapp
    developer portal (New version > Release info > public key)

Optional environment variables:
  TRANSLITE_DEVELOPER_ID    codesign identity (default: Developer ID Application)
  TRANSLITE_NOTARY_PROFILE  notarytool Keychain profile (default: TransLite)
  TRANSLITE_TEAM_ID         Apple Developer team (default: 2DBHSD6G6F)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

required_tools=(codesign ditto lipo security sips spctl xcodebuild xcodegen xcrun)
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: required tool '$tool' is not installed" >&2
        exit 1
    fi
done

if [ ! -f "$PUBLIC_KEY" ]; then
    echo "Error: $PUBLIC_KEY is missing." >&2
    echo "Download setappPublicKey.pem from developer.setapp.com (New version >" >&2
    echo "Release info) and place it there, then run 'xcodegen generate'." >&2
    exit 1
fi

if [ ! -f "$XCCONFIG" ] || ! grep -Eq '^SETAPP_AI_OAUTH_CLIENT_ID = .+' "$XCCONFIG" || \
   ! grep -Eq '^SETAPP_AI_OAUTH_SECRET = .+' "$XCCONFIG"; then
    echo "Error: $XCCONFIG is missing or has empty OAuth credentials." >&2
    echo "Copy Setapp.xcconfig.sample and fill in the OAuth client values" >&2
    echo "from developer.setapp.com (Apps > OAuth Clients)." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID" >/dev/null; then
    echo "Error: signing identity '$DEVELOPER_ID' is not available in Keychain" >&2
    exit 1
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_YML")"
BUILD_NUMBER="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJECT_YML")"
ZIP_PATH="$RELEASE_DIR/TransLite-Setapp-$VERSION.zip"

WORK_DIR="$(mktemp -d "${TMPDIR%/}/translite-setapp.XXXXXX")"
DERIVED_DATA="$WORK_DIR/DerivedData"
STAGING_DIR="$WORK_DIR/archive"
APP_PATH="$STAGING_DIR/TransLite.app"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Regenerating the Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

echo "Building TransLiteSetapp $VERSION ($BUILD_NUMBER), Release universal..."
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme TransLiteSetapp \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    clean build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/TransLite.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "Error: Release app was not found at $BUILT_APP" >&2
    exit 1
fi

mkdir -p "$STAGING_DIR" "$RELEASE_DIR"
ditto "$BUILT_APP" "$APP_PATH"

echo "Verifying the bundle..."
PLIST="$APP_PATH/Contents/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
if [ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
    echo "Error: bundle id is '$BUNDLE_ID', expected '$EXPECTED_BUNDLE_ID'" >&2
    exit 1
fi
for key in CFBundleName CFBundleIconFile CFBundleVersion CFBundleShortVersionString NSUpdateSecurityPolicy MPSupportedArchitectures; do
    if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
        echo "Error: required Info.plist key '$key' is missing" >&2
        exit 1
    fi
done
if ! lipo -info "$APP_PATH/Contents/MacOS/TransLite" | grep -q "x86_64 arm64"; then
    echo "Error: the binary is not a universal (x86_64 + arm64) build" >&2
    exit 1
fi
if [ ! -f "$APP_PATH/Contents/Resources/setappPublicKey.pem" ]; then
    echo "Error: setappPublicKey.pem was not copied into the app bundle." >&2
    echo "Run 'xcodegen generate' after adding the file and build again." >&2
    exit 1
fi
if [ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]; then
    echo "Error: Sparkle.framework must not ship in the Setapp build" >&2
    exit 1
fi
CLIENT_ID_VALUE="$(/usr/libexec/PlistBuddy -c 'Print :SetappAIOAuthClientID' "$PLIST")"
if [ -z "$CLIENT_ID_VALUE" ]; then
    echo "Error: SetappAIOAuthClientID is empty in the built app" >&2
    exit 1
fi

echo "Signing the application..."
codesign --deep --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNED_TEAM_ID="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
if [ "$SIGNED_TEAM_ID" != "$TEAM_ID" ]; then
    echo "Error: the app was signed by team '$SIGNED_TEAM_ID', expected '$TEAM_ID'" >&2
    exit 1
fi

echo "Notarizing..."
NOTARIZE_ZIP="$WORK_DIR/notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "Preparing the submission archive..."
ICON_WIDTH="$(sips -g pixelWidth "$ICON_SOURCE" | awk '/pixelWidth/ { print $2 }')"
if [ "$ICON_WIDTH" != "1024" ]; then
    echo "Error: $ICON_SOURCE is ${ICON_WIDTH}px wide, Setapp requires 1024x1024" >&2
    exit 1
fi
# Setapp's uploader only accepts this exact filename, next to the .app.
# Strip extended attributes or ditto embeds them as ._AppIcon.png metadata.
cp "$ICON_SOURCE" "$STAGING_DIR/AppIcon.png"
xattr -c "$STAGING_DIR/AppIcon.png"

rm -f "$ZIP_PATH"
ditto --norsrc --noextattr -c -k "$STAGING_DIR" "$ZIP_PATH"

echo "Verifying the archive..."
VERIFY_DIR="$WORK_DIR/verify"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
if find "$VERIFY_DIR" \( -name "__MACOSX" -o -name "._*" \) | grep -q .; then
    echo "Error: the archive contains Finder metadata (__MACOSX or ._ files)" >&2
    exit 1
fi
if [ ! -d "$VERIFY_DIR/TransLite.app" ] || [ ! -f "$VERIFY_DIR/AppIcon.png" ]; then
    echo "Error: unexpected archive layout:" >&2
    find "$VERIFY_DIR" -maxdepth 2 >&2
    exit 1
fi

echo
echo "TransLite (Setapp) $VERSION ($BUILD_NUMBER) is ready for submission."
echo "Archive: $ZIP_PATH"
echo "Upload it at https://developer.setapp.com (your app > New version)."
