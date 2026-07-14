#!/usr/bin/env bash
# Build Nudge.app: generate icon, compile, assemble the bundle, and codesign.
# Override the signing identity with:  SIGN_ID="Your Identity" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="Nudge.app"
BUILD="build"
rm -rf "$APP" "$BUILD"
mkdir -p "$BUILD"

echo "==> icon"
swiftc -O make-icon.swift -o "$BUILD/make-icon"
"$BUILD/make-icon" "$BUILD/icon-1024.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for pair in \
  "icon_16x16:16" "icon_16x16@2x:32" \
  "icon_32x32:32" "icon_32x32@2x:64" \
  "icon_128x128:128" "icon_128x128@2x:256" \
  "icon_256x256:256" "icon_256x256@2x:512" \
  "icon_512x512:512" "icon_512x512@2x:1024"; do
  name="${pair%%:*}"; sz="${pair##*:}"
  sips -z "$sz" "$sz" "$BUILD/icon-1024.png" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "==> compile"
swiftc -O -swift-version 5 \
  -framework AppKit -framework UserNotifications \
  Sources/main.swift -o "$BUILD/Nudge"

echo "==> assemble bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Nudge" "$APP/Contents/MacOS/Nudge"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> sign"
IDENTITY="${SIGN_ID:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/LocalSign/{print $2; exit}')
fi
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "Signed with: $IDENTITY"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature|Authority' || true

echo "==> built $(pwd)/$APP"
