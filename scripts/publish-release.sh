#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/TransLite"
PROJECT_FILE="$PROJECT_DIR/TransLite.xcodeproj"
PROJECT_YML="$PROJECT_DIR/project.yml"
APPCAST_FILE="$ROOT_DIR/appcast.xml"
RELEASE_DIR="$ROOT_DIR/releases"
REPOSITORY="${TRANSLITE_GITHUB_REPOSITORY:-davizgarzia/TransLite}"
DEVELOPER_ID="${TRANSLITE_DEVELOPER_ID:-Developer ID Application}"
NOTARY_PROFILE="${TRANSLITE_NOTARY_PROFILE:-TransLite}"
TEAM_ID="${TRANSLITE_TEAM_ID:-2DBHSD6G6F}"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/publish-release.sh VERSION BUILD_NUMBER --note "Change" [--note "Another change"]

Example:
  ./scripts/publish-release.sh 1.1.4 15 \
    --note "Improved translation errors" \
    --note "Fixed the settings screen"

The script builds, signs, notarizes and publishes the DMG, updates Sparkle's
appcast, commits the release, pushes its tag, creates a GitHub release and then
pushes main. It must be run from a clean main branch.

Optional environment variables:
  TRANSLITE_DEVELOPER_ID       codesign identity (default: Developer ID Application)
  TRANSLITE_NOTARY_PROFILE     notarytool Keychain profile (default: TransLite)
  TRANSLITE_TEAM_ID            Apple Developer team (default: 2DBHSD6G6F)
  TRANSLITE_GITHUB_REPOSITORY  owner/repository (default: davizgarzia/TransLite)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

VERSION="${1:-}"
BUILD_NUMBER="${2:-}"
if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    usage
    exit 1
fi
shift 2

NOTES=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --note)
            if [ -z "${2:-}" ]; then
                echo "Error: --note requires text" >&2
                exit 1
            fi
            NOTES+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must use MAJOR.MINOR.PATCH, for example 1.1.4" >&2
    exit 1
fi
if ! [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: build number must be a positive integer" >&2
    exit 1
fi
if [ "${#NOTES[@]}" -eq 0 ]; then
    echo "Error: add at least one release note with --note" >&2
    exit 1
fi

required_tools=(awk codesign create-dmg ditto gh git security sed spctl xcodebuild xcodegen xmllint xcrun)
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: required tool '$tool' is not installed" >&2
        exit 1
    fi
done

cd "$ROOT_DIR"

if [ "$(git branch --show-current)" != "main" ]; then
    echo "Error: releases must be created from the main branch" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: the working tree is not clean. Commit or stash your changes first:" >&2
    git status --short >&2
    exit 1
fi

CURRENT_VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_YML")"
CURRENT_BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJECT_YML")"
if [ "$VERSION" = "$CURRENT_VERSION" ]; then
    echo "Error: $VERSION is already the current version" >&2
    exit 1
fi
if [ "$BUILD_NUMBER" -le "$CURRENT_BUILD" ]; then
    echo "Error: build number must be greater than $CURRENT_BUILD" >&2
    exit 1
fi

TAG="v$VERSION"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag $TAG already exists locally" >&2
    exit 1
fi

echo "Checking GitHub authentication and repository state..."
gh auth status --hostname github.com >/dev/null
git fetch origin main --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Error: local main and origin/main differ. Synchronize them before releasing." >&2
    exit 1
fi
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
    echo "Error: GitHub release $TAG already exists" >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID" >/dev/null; then
    echo "Error: signing identity '$DEVELOPER_ID' is not available in Keychain" >&2
    echo "Set TRANSLITE_DEVELOPER_ID if the certificate has a different name or hash." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR%/}/translite-release.XXXXXX")"
DERIVED_DATA="$WORK_DIR/DerivedData"
STAGING_DIR="$WORK_DIR/dmg"
APP_PATH="$STAGING_DIR/TransLite.app"
DMG_PATH="$RELEASE_DIR/TransLite-$VERSION.dmg"
ENTRY_FILE="$WORK_DIR/appcast-entry.xml"
UPDATED_APPCAST="$WORK_DIR/appcast.xml"
RELEASE_COMMITTED=false
cleanup() {
    status=$?
    trap - EXIT
    rm -rf "$WORK_DIR"
    if [ "$status" -ne 0 ] && [ "$RELEASE_COMMITTED" = false ]; then
        echo "Release failed before the commit; restoring generated version files." >&2
        git -C "$ROOT_DIR" restore -- \
            TransLite/project.yml \
            TransLite/TransLite.xcodeproj/project.pbxproj \
            appcast.xml
    fi
    exit "$status"
}
trap cleanup EXIT

echo "Updating version to $VERSION ($BUILD_NUMBER)..."
sed -i '' -E 's/MARKETING_VERSION: "[^"]+"/MARKETING_VERSION: "'"$VERSION"'"/' "$PROJECT_YML"
sed -i '' -E 's/CURRENT_PROJECT_VERSION: "[^"]+"/CURRENT_PROJECT_VERSION: "'"$BUILD_NUMBER"'"/' "$PROJECT_YML"
if ! grep -F "MARKETING_VERSION: \"$VERSION\"" "$PROJECT_YML" >/dev/null || \
   ! grep -F "CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"" "$PROJECT_YML" >/dev/null; then
    echo "Error: version fields could not be updated in project.yml" >&2
    exit 1
fi

echo "Regenerating the Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

echo "Building the Release configuration..."
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme TransLite \
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

echo "Signing the application..."
codesign --deep --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNED_TEAM_ID="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
if [ "$SIGNED_TEAM_ID" != "$TEAM_ID" ]; then
    echo "Error: the app was signed by team '$SIGNED_TEAM_ID', expected '$TEAM_ID'" >&2
    exit 1
fi

echo "Creating and signing the DMG..."
rm -f "$DMG_PATH"
create-dmg \
    --volname "TransLite $VERSION" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "TransLite.app" 150 185 \
    --app-drop-link 450 185 \
    --hide-extension "TransLite.app" \
    "$DMG_PATH" \
    "$STAGING_DIR"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_PATH"

echo "Notarizing the DMG..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

SPARKLE_BIN="$(find "$DERIVED_DATA/SourcePackages/artifacts" -name sign_update -type f | head -1)"
if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Sparkle's sign_update executable was not found" >&2
    exit 1
fi

SPARKLE_KEYS_BIN="$(find "$DERIVED_DATA/SourcePackages/artifacts" -name generate_keys -type f | head -1)"
if [ -z "$SPARKLE_KEYS_BIN" ]; then
    echo "Error: Sparkle's generate_keys executable was not found" >&2
    exit 1
fi

APP_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_PATH/Contents/Info.plist")"
KEYCHAIN_PUBLIC_KEY="$("$SPARKLE_KEYS_BIN" -p)"
if [ "$APP_PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]; then
    echo "Error: the Sparkle private key in Keychain does not match SUPublicEDKey." >&2
    echo "App key:      $APP_PUBLIC_KEY" >&2
    echo "Keychain key: $KEYCHAIN_PUBLIC_KEY" >&2
    exit 1
fi

echo "Signing the update for Sparkle..."
SPARKLE_ATTRIBUTES="$("$SPARKLE_BIN" "$DMG_PATH")"
if [[ "$SPARKLE_ATTRIBUTES" != *"sparkle:edSignature="* ]] || [[ "$SPARKLE_ATTRIBUTES" != *"length="* ]]; then
    echo "Error: unexpected output from Sparkle sign_update: $SPARKLE_ATTRIBUTES" >&2
    exit 1
fi

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

{
    echo "        <item>"
    echo "            <title>Version $VERSION</title>"
    echo "            <pubDate>$(LC_ALL=C date -R)</pubDate>"
    echo "            <sparkle:version>$BUILD_NUMBER</sparkle:version>"
    echo "            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"
    echo "            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
    echo "            <description><![CDATA["
    echo "                <h2>TransLite $VERSION</h2>"
    echo "                <ul>"
    for note in "${NOTES[@]}"; do
        echo "                    <li>$(xml_escape "$note")</li>"
    done
    echo "                </ul>"
    echo "            ]]></description>"
    echo "            <enclosure"
    echo "                url=\"https://github.com/$REPOSITORY/releases/download/$TAG/TransLite-$VERSION.dmg\""
    echo "                $SPARKLE_ATTRIBUTES"
    echo "                type=\"application/octet-stream\" />"
    echo "        </item>"
} > "$ENTRY_FILE"

awk -v entry_file="$ENTRY_FILE" -v version="$VERSION" '
    /<!-- Current version:/ && !inserted {
        match($0, /^[[:space:]]*/)
        indent = substr($0, RSTART, RLENGTH)
        print indent "<!-- Current version: " version " -->"
        while ((getline line < entry_file) > 0) print line
        close(entry_file)
        inserted = 1
        next
    }
    { print }
    END { if (!inserted) exit 42 }
' "$APPCAST_FILE" > "$UPDATED_APPCAST" || {
    echo "Error: could not find the current-version marker in appcast.xml" >&2
    exit 1
}
mv "$UPDATED_APPCAST" "$APPCAST_FILE"

echo "Validating the generated appcast..."
xmllint --noout "$APPCAST_FILE"

cd "$ROOT_DIR"
git add "$PROJECT_YML" "$PROJECT_FILE/project.pbxproj" "$APPCAST_FILE"
git diff --cached --check
git commit -m "Release $TAG"
RELEASE_COMMITTED=true
git tag -a "$TAG" -m "TransLite $VERSION"

echo "Uploading the tag and a draft GitHub release..."
git push origin "$TAG"

GH_NOTES="$WORK_DIR/github-notes.md"
for note in "${NOTES[@]}"; do
    printf -- '- %s\n' "$note" >> "$GH_NOTES"
done
gh release create "$TAG" "$DMG_PATH" \
    --repo "$REPOSITORY" \
    --verify-tag \
    --draft \
    --title "TransLite $VERSION" \
    --notes-file "$GH_NOTES"

echo "Publishing main and making the GitHub release public..."
git push origin main
gh release edit "$TAG" --repo "$REPOSITORY" --draft=false --latest

echo
echo "TransLite $VERSION ($BUILD_NUMBER) was published successfully."
echo "DMG: $DMG_PATH"
echo "Release: https://github.com/$REPOSITORY/releases/tag/$TAG"
