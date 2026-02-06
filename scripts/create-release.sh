#!/bin/bash

# Script to create a TransLite release with signing, DMG and notarization
# Usage: ./scripts/create-release.sh 1.1.0

set -e

VERSION=$1
DEVELOPER_ID="0FCEEAA4861A3809015D60D8BD083B396BD79016"
NOTARY_PROFILE="TransLite"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.1.0"
    exit 1
fi

echo "=== Creating TransLite v$VERSION release ==="
echo ""

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/TransLite"
RELEASE_DIR="$PROJECT_DIR/releases"
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*" 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: sign_update not found"
    echo "Make sure you have built the project at least once"
    exit 1
fi

# 1. Regenerate project
echo "1/8. Regenerating project..."
cd "$BUILD_DIR"
xcodegen generate 2>&1 | grep -E "(Created|error)" || true

# 2. Build
echo "2/8. Building..."
xcodebuild -project TransLite.xcodeproj -scheme TransLite -configuration Release clean build 2>&1 | grep -E "(BUILD|error:)" || true

# 3. Copy app
echo "3/8. Preparing app..."
mkdir -p "$RELEASE_DIR"
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/TransLite-*/Build/Products/Release -name "TransLite.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Built app not found"
    exit 1
fi

rm -rf "$RELEASE_DIR/TransLite-$VERSION.app"
cp -R "$APP_PATH" "$RELEASE_DIR/TransLite-$VERSION.app"

# 4. Sign the app (deep signing for included frameworks)
echo "4/8. Signing app with Developer ID..."
codesign --deep --force --options runtime --sign "$DEVELOPER_ID" "$RELEASE_DIR/TransLite-$VERSION.app"
codesign --verify --verbose "$RELEASE_DIR/TransLite-$VERSION.app"

# 5. Create DMG with professional design
echo "5/8. Creating DMG with professional design..."
DMG_PATH="$RELEASE_DIR/TransLite-$VERSION.dmg"
rm -f "$DMG_PATH"

# Temporarily rename app so it's called TransLite.app in the DMG
mv "$RELEASE_DIR/TransLite-$VERSION.app" "$RELEASE_DIR/TransLite.app"

# Create DMG with create-dmg (includes Applications alias automatically)
create-dmg \
    --volname "TransLite $VERSION" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "TransLite.app" 150 185 \
    --app-drop-link 450 185 \
    --hide-extension "TransLite.app" \
    "$DMG_PATH" \
    "$RELEASE_DIR/TransLite.app"

# Restore original name
mv "$RELEASE_DIR/TransLite.app" "$RELEASE_DIR/TransLite-$VERSION.app"

# 6. Sign DMG
echo "6/8. Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"

# 7. Notarize
echo "7/8. Notarizing with Apple (this may take 2-5 minutes)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

# Staple the ticket
echo "    Applying staple..."
xcrun stapler staple "$DMG_PATH"

# 8. Sign for Sparkle
echo "8/8. Generating Sparkle signature..."
SIGNATURE=$("$SPARKLE_BIN" "$DMG_PATH" 2>&1)
SIZE=$(stat -f%z "$DMG_PATH")

echo ""
echo "=========================================="
echo "   RELEASE v$VERSION READY"
echo "=========================================="
echo ""
echo "File: $DMG_PATH"
echo "Size: $SIZE bytes"
echo ""
echo "Add this to appcast.xml (above the previous item):"
echo ""
echo "        <item>"
echo "            <title>Version $VERSION</title>"
echo "            <pubDate>$(date -R)</pubDate>"
echo "            <sparkle:version>BUILD_NUMBER_HERE</sparkle:version>"
echo "            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"
echo "            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
echo "            <description><![CDATA["
echo "                <h2>TransLite $VERSION</h2>"
echo "                <ul>"
echo "                    <li>Changes here</li>"
echo "                </ul>"
echo "            ]]></description>"
echo "            <enclosure"
echo "                url=\"https://github.com/davizgarzia/TransLite/releases/download/v$VERSION/TransLite-$VERSION.dmg\""
echo "                $SIGNATURE"
echo "                length=\"$SIZE\""
echo "                type=\"application/octet-stream\" />"
echo "        </item>"
echo ""
echo "Next steps:"
echo "1. gh release create v$VERSION $DMG_PATH --title \"TransLite $VERSION\" --notes \"Changes...\""
echo "2. Update appcast.xml with the XML above"
echo "3. git add appcast.xml && git commit -m \"Release v$VERSION\" && git push"
