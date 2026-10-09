#!/usr/bin/env bash
# Builds AgentSwitch.app (menu-bar only) into ./build. Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

# Native arch by default. Set UNIVERSAL=1 for arm64+x86_64 (requires full Xcode).
ARCHS=()
[ "${UNIVERSAL:-0}" = "1" ] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/AgentSwitch"

APP="build/AgentSwitch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgentSwitch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: render once, then build the .icns.
if [ ! -f build/AppIcon.icns ]; then
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift scripts/make_icon.swift build/icon_1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"   # ad-hoc; use your Developer ID to distribute
echo "Built $APP"
