#!/bin/bash
# Builds ReadItOut.app from the Swift package. Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# App icon: redrawn whenever make_icon.swift changes.
if [ ! -f Resources/AppIcon.icns ] || [ Resources/make_icon.swift -nt Resources/AppIcon.icns ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    swift Resources/make_icon.swift "$ICONSET/icon_512x512@2x.png"
    for px in 16 32 128 256 512; do
        sips -z $px $px "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
        sips -z $((px * 2)) $((px * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
    done
    iconutil --convert icns --output Resources/AppIcon.icns "$ICONSET"
    rm -rf "$(dirname "$ICONSET")"
fi

APP="build/ReadItOut.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ReadItOut" "$APP/Contents/MacOS/ReadItOut"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/tts_server.py "$APP/Contents/Resources/tts_server.py"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad hoc signature so macOS will launch it locally.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
