#!/bin/bash
# Builds build/MacHome.app with Apple's Command Line Tools (xcode-select --install).
# Xcode and an Apple ID are not needed.
#
# This calls the Swift compiler directly instead of `swift build`: with only the Command Line
# Tools on macOS 12, Swift Package Manager fails with "no such module 'PackageDescription'".
#
# The app is built for this Mac's processor. Set ARCH=x86_64 or ARCH=arm64 to choose another.
set -euo pipefail
cd "$(dirname "$0")/.."

arch="${ARCH:-$(uname -m)}"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
app="build/MacHome.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

xcrun swiftc -O -wmo -swift-version 5 \
    -target "$arch-apple-macos12.0" -sdk "$sdk" \
    -module-name MacHome \
    -o "$app/Contents/MacOS/MacHome" \
    Sources/MacHome/*.swift
cp Support/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signing needs no developer account. It gives macOS a stable identity for the
# Accessibility permission until the next rebuild.
codesign --force --sign - "$app"

echo "Built $app"
