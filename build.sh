#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/dist/Here/materialTun.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HELPERS="$CONTENTS/Library/HelperTools"
ICONSET="$ROOT/.build/AppIcon.iconset"

cd "$ROOT"
swift build -c release --arch arm64
swift build -c release --arch x86_64

rm -rf "$APP" "$ICONSET"
mkdir -p "$MACOS" "$RESOURCES" "$HELPERS" "$ICONSET"

lipo -create \
  "$ROOT/.build/arm64-apple-macosx/release/materialTun" \
  "$ROOT/.build/x86_64-apple-macosx/release/materialTun" \
  -output "$MACOS/materialTun"
lipo -create \
  "$ROOT/.build/arm64-apple-macosx/release/materialTunHelper" \
  "$ROOT/.build/x86_64-apple-macosx/release/materialTunHelper" \
  -output "$HELPERS/materialTunHelper"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "/tmp/happ-dmg/Happ.app/Contents/MacOS/core/xray" "$RESOURCES/xray"
cp "/tmp/happ-dmg/Happ.app/Contents/MacOS/tun/sing-box" "$RESOURCES/sing-box"
cp "/tmp/happ-dmg/Happ.app/Contents/Resources/geoip.dat" "$RESOURCES/geoip.dat"
cp "/tmp/happ-dmg/Happ.app/Contents/Resources/geosite.dat" "$RESOURCES/geosite.dat"
chmod +x "$MACOS/materialTun" "$HELPERS/materialTunHelper" "$RESOURCES/xray" "$RESOURCES/sing-box"

sips -s format png "$ROOT/Resources/AppIcon.png" --out "$ROOT/.build/AppIcon-source.png" >/dev/null
sips -z 1024 1024 "$ROOT/.build/AppIcon-source.png" --out "$ROOT/.build/AppIcon-1024.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/.build/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ROOT/.build/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
xattr -cr "$APP"
echo "$APP"
