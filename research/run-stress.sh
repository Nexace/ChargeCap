#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
log=${1:-"$PWD/research/UI-Stress.log"}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/chargecap-stress.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
app="$temporary/ChargeCap UI Stress.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.amogh.ChargeCap.UIStress "$app/Contents/Info.plist"
plutil -replace CFBundleName -string 'ChargeCap UI Stress' "$app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'ChargeCap UI Stress' "$app/Contents/Info.plist"
cp artwork/ChargeCap.icns "$app/Contents/Resources/ChargeCap.icns"
xcrun clang -arch arm64 -fobjc-arc -Os -DNDEBUG -Wall -Wextra -Werror \
  -mmacosx-version-min=26.4 -framework AppKit -framework QuartzCore -framework IOSurface \
  research/stress-ui.m -Wl,-dead_strip -o "$app/Contents/MacOS/ChargeCap"
codesign --force --sign - "$app"
open -W -n -a "$app" --stdout "$log" --stderr "$log.errors"
cat "$log"
