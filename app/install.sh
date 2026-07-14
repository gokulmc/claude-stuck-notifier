#!/usr/bin/env bash
# Build + install Nudge: to /Applications, register the nudge:// scheme, and set
# it to start at login (so it's alive to catch notification clicks).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
SIGNED_APP="${TMPDIR:-/tmp}/nudge-stage/Nudge.app"
if [ ! -d "$SIGNED_APP" ]; then
  echo "build did not produce $SIGNED_APP" >&2; exit 1
fi

APP_DST="/Applications/Nudge.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
PLIST="$HOME/Library/LaunchAgents/com.gokulmc.nudge.plist"
LABEL="com.gokulmc.nudge"
DOMAIN="gui/$(id -u)"

echo "==> installing to $APP_DST"
pkill -x Nudge 2>/dev/null || true             # stop any running instance first
rm -rf "$APP_DST"
ditto "$SIGNED_APP" "$APP_DST"                 # temp (non-synced) -> /Applications: signature stays intact
"$LSREG" -f "$APP_DST" 2>/dev/null || true     # register the nudge:// scheme deterministically

# LaunchAgent: start at login. "--agent" marks the launchd instance as the
# authoritative one (it clears any stray instances on launch). ProgramArguments
# points at the binary INSIDE the bundle so Bundle.main / CFBundleIdentifier
# resolve (required by UNUserNotificationCenter).
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
		<string>--agent</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST_EOF

# Reload cleanly with the modern API; kickstart forces a fresh start.
launchctl bootout   "$DOMAIN/$LABEL"        2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"      2>/dev/null || true
launchctl kickstart -k "$DOMAIN/$LABEL"     2>/dev/null || true

# Wait (bounded) until the launchd instance is actually up, so nothing else can
# race it. `open nudge://…` after this routes to the running agent.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x Nudge >/dev/null 2>&1 && break
  /bin/sleep 0.3
done

if pgrep -x Nudge >/dev/null 2>&1; then
  echo "==> Nudge running (pid $(pgrep -x Nudge)), starts at login."
else
  echo "==> WARNING: Nudge did not come up; check: launchctl print $DOMAIN/$LABEL"
fi
echo "    Grant the notification prompt the first time."
echo "    The hook auto-detects $APP_DST and routes banners to it."
