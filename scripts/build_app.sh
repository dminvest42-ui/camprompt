#!/usr/bin/env bash
# Builds CamPrompt.app from the SwiftPM binary and packages a .dmg.
# Runs on macOS (GitHub Actions runner or a local Mac).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_DIR="$ROOT/dist/CamPrompt.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

cd "$ROOT"

echo "==> swift build -c release"
swift build -c release

echo "==> Bundling CamPrompt.app"
rm -rf "$ROOT/dist"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/CamPrompt" "$MACOS_DIR/CamPrompt"
chmod +x "$MACOS_DIR/CamPrompt"

# Stamp the version into Info.plist
sed "s/<string>0\.1\.0<\/string>/<string>${VERSION}<\/string>/" "Resources/Info.plist" > "$CONTENTS/Info.plist"

# App icon: build .icns from the source PNG using sips + iconutil
if [[ -f "Resources/icon_1024.png" ]]; then
    echo "==> Building AppIcon.icns"
    ICONSET="$ROOT/dist/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "Resources/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "Resources/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Creating dmg"
DMG_STAGING="$ROOT/dist/dmg"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "CamPrompt" -srcfolder "$DMG_STAGING" -ov -format UDZO \
    "$ROOT/dist/CamPrompt-${VERSION}.dmg"
rm -rf "$DMG_STAGING"

echo "==> Done:"
ls -la "$ROOT/dist"
shasum -a 256 "$ROOT/dist/CamPrompt-${VERSION}.dmg"
