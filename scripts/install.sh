#!/bin/bash
# Builds MacHome, installs it in ~/Applications and starts it now and at every login.
set -euo pipefail
cd "$(dirname "$0")/.."

label="local.machome.launcher"
dest="$HOME/Applications/MacHome.app"
plist="$HOME/Library/LaunchAgents/$label.plist"

scripts/build.sh

# Stop any running copy before replacing it (unloading first so launchd doesn't restart it).
launchctl unload "$plist" 2>/dev/null || true
pkill -x MacHome 2>/dev/null || true

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$dest"
cp -R build/MacHome.app "$dest"

# Starts at login and restarts after a crash, but not after Quit.
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$dest/Contents/MacOS/MacHome</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
EOF

launchctl load -w "$plist"
echo "Installed $dest. It starts automatically at login."
echo "If you had granted Accessibility access before, remove MacHome from that list and add it again (rebuilding changes its signature)."
