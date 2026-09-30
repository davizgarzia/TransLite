#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/TransLite/TransLite.xcodeproj"
DERIVED_DATA="${TRANSLITE_DERIVED_DATA:-$ROOT_DIR/.build/DerivedData}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/TransLite.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/TransLite"

SHOULD_CLEAN=false
SHOULD_OPEN=true
SCHEME=TransLite
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) SHOULD_CLEAN=true ;;
        --build-only) SHOULD_OPEN=false ;;
        --setapp) SCHEME=TransLiteSetapp ;;
        -h|--help)
            echo "Usage: $0 [--clean] [--build-only] [--setapp]"
            exit 0
            ;;
        *)
            echo "Usage: $0 [--clean] [--build-only] [--setapp]" >&2
            exit 1
            ;;
    esac
    shift
done

if [ "$SHOULD_CLEAN" = true ]; then
    echo "Cleaning the development build..."
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA" \
        clean
fi

echo "Building $SCHEME (Debug)..."
if [ "$SCHEME" = "TransLiteSetapp" ]; then
    # The Setapp agent identifies the app by its code signature, so the
    # Setapp build must be signed with the real Developer ID even for
    # local testing (ad-hoc signatures fail activation).
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet \
        build
else
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet \
        CODE_SIGN_IDENTITY=- \
        CODE_SIGNING_REQUIRED=NO \
        build
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: build succeeded but the app was not found at $APP_PATH" >&2
    exit 1
fi

# Stop only the development binary produced by this script. This avoids
# accidentally closing an installed release build with the same bundle ID.
if [ "$SHOULD_OPEN" = false ]; then
    echo "Development build ready at $APP_PATH"
    exit 0
fi

if pgrep -f "$EXECUTABLE_PATH" >/dev/null 2>&1; then
    echo "Closing the previous development build..."
    pkill -f "$EXECUTABLE_PATH" || true
fi

echo "Opening $APP_PATH"
open -n "$APP_PATH"
