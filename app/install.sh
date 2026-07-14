#!/usr/bin/env bash
# Build + install Nudge: to /Applications, register the nudge:// scheme, and set
# it to start at login (so it's alive to catch notification clicks).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP_DST="/Applications/Nudge.app"
echo "==> installing to $APP_DST"
pkill -x Nudge 2>/dev/null || true      # stop any running instance before replacing
rm -rf "$APP_DST"
cp -R Nudge.app "$APP_DST"

# LaunchAgent: start at login. ProgramArguments points at the binary INSIDE the
# bundle so Bundle.main / CFBundleIdentifier resolve (required by UNUserNotificationCenter).
PLIST="$HOME/Library/LaunchAgents/com.gokulmc.nudge.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.gokulmc.nudge</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/Nudge.app/Contents/MacOS/Nudge</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST_EOF

# (Re)load the agent — this also launches it now, triggering the one-time
# notification-permission prompt on first install.
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST" 2>/dev/null || true

echo
echo "Nudge installed and running (starts at login)."
echo "  • Grant the notification prompt the first time."
echo "  • The hook auto-detects $APP_DST and routes banners to it."
echo "  • To focus a specific window on click, Nudge uses VS Code's 'code' CLI."
