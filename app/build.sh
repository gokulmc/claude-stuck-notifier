#!/usr/bin/env bash
# Build Nudge.app: generate icon, compile, assemble, and codesign.
# Builds in a NON-synced temp staging dir because the repo may live under an
# iCloud-managed folder (Desktop/Documents), whose file provider stamps
# com.apple.FinderInfo on the .app and breaks codesign. The pristine signed
# bundle is left at $STAGE/Nudge.app for install.sh to ditto into /Applications.
# Override the signing identity with:  SIGN_ID="Your Identity" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

STAGE="${TMPDIR:-/tmp}/nudge-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
APP="$STAGE/Nudge.app"

echo "==> icon"
swiftc -O make-icon.swift -o "$STAGE/make-icon"
"$STAGE/make-icon" "$STAGE/icon-1024.png"
ICONSET="$STAGE/AppIcon.iconset"; mkdir -p "$ICONSET"
for pair in \
  "icon_16x16:16" "icon_16x16@2x:32" \
  "icon_32x32:32" "icon_32x32@2x:64" \
  "icon_128x128:128" "icon_128x128@2x:256" \
  "icon_256x256:256" "icon_256x256@2x:512" \
  "icon_512x512:512" "icon_512x512@2x:1024"; do
  name="${pair%%:*}"; sz="${pair##*:}"
  sips -z "$sz" "$sz" "$STAGE/icon-1024.png" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/AppIcon.icns"

echo "==> compile"
swiftc -O -swift-version 5 \
  -framework AppKit -framework UserNotifications \
  Sources/main.swift -o "$STAGE/Nudge"

echo "==> assemble bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$STAGE/Nudge" "$APP/Contents/MacOS/Nudge"
cp Info.plist "$APP/Contents/Info.plist"
cp "$STAGE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> sign"
xattr -cr "$APP" 2>/dev/null || true
IDENTITY="${SIGN_ID:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/LocalSign/{print $2; exit}')
fi
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --strict "$APP" && echo "signature verified ($IDENTITY)"

# Convenience copy for standalone testing (may be re-stamped on synced disks;
# install.sh always uses the pristine staged copy below).
rm -rf ./Nudge.app; ditto "$APP" ./Nudge.app 2>/dev/null || true

echo "==> signed bundle staged at $APP"
