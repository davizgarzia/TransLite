#!/bin/bash

# TranslateBar Setup Script
# This script generates the Xcode project using xcodegen

set -e

echo "TranslateBar Setup"
echo "=================="
echo ""

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen is not installed."
    echo ""
    echo "Install it with Homebrew:"
    echo "  brew install xcodegen"
    echo ""
    echo "Or download from: https://github.com/yonaskolb/XcodeGen"
    exit 1
fi

# Navigate to the TranslateBar directory
cd "$(dirname "$0")/TranslateBar"

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Success! Xcode project generated."
echo ""
echo "Next steps:"
echo "1. Open TranslateBar.xcodeproj in Xcode"
echo "2. Select your signing team in project settings"
echo "3. Build and run (Cmd+R)"
echo ""
echo "Opening project..."
open TranslateBar.xcodeproj
