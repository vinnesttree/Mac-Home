#!/bin/bash
# Builds build/MacHome.app with Apple's Command Line Tools (xcode-select --install).
# Xcode and an Apple ID are not needed. Extra arguments go to `swift build`, e.g. --arch x86_64.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release ${1+"$@"}
bin_dir="$(swift build -c release ${1+"$@"} --show-bin-path)"

app="build/MacHome.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/MacHome" "$app/Contents/MacOS/MacHome"
cp Support/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signing needs no developer account. It gives macOS a stable identity for the
# Accessibility permission until the next rebuild.
codesign --force --sign - "$app"

echo "Built $app"
